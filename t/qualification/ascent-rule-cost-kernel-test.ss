;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/positive-plan
        (only-in :std/list/list append-map)
        (prefix-in :clan/poo/testing/property property.)
        (prefix-in :clan/poo/testing/property/generator generator.)
        (prefix-in :clan/poo/testing/property/model model.)
        (prefix-in :clan/poo/testing/property/replay replay.)
        (only-in :clan/poo/testing/property/test require-passed)
        (only-in :gerbil-ascent/program/index gerbil-ascent-make-row-indexes
                 row-indexes-plan-rules! row-indexes-rows)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/t/qualification/fixtures/semi-naive/oracle finite-domain-closure))
(export ascent-rule-cost-kernel-test)
(def (read-count cost name) (cdr (assq name (positive-plan-cost-snapshot cost))))
(def (fixture)
  (gerbil-ascent-compile-positive-plan
    (list (vector 2 '((variable . x) (variable . y)))
          (vector 3 '((variable . x) (variable . y))))
    (list (vector 'atom (vector 0 '((variable . x)) [] [] []))
          (vector 'atom (vector 1 '((variable . x) (variable . y)) [] [] [])))))
(def (inputs atom frame delta? terms)
  (case (vector-ref atom 0) ((0) '((0) (1))) ((1) '((0 2) (1 3) (1 4)))))
;;; Use POO's existing model/generator/shrink/replay protocol. Commands replace
;;; the two finite row cuts; the reference is ordered filtering, not an index.
(def (mask-rows mask)
  (filter-map (lambda (i) (and (not (zero? (bitwise-and mask (arithmetic-shift 1 i))))
                              (list (quotient i 2) (modulo i 2)))) (iota 4)))
(def (cut-command? value)
  (and (vector? value) (= (vector-length value) 2)
       (andmap (lambda (n) (and (exact-integer? n) (<= 0 n) (< n 16))) (vector->list value))
       (= (bitwise-and (vector-ref value 0) (vector-ref value 1)) (vector-ref value 1))))
(def (reference-probes command)
  (append-map
   (lambda (mask)
     (append-map (lambda (key)
                   (let (rows (filter (lambda (row) (= (car row) key)) (mask-rows mask)))
                     (list rows rows))) '(0 1))) (vector->list command)))
(def cut-model
  (model.make-model (lambda () (vector 0 0)) (lambda (_state _command) #t)
    (lambda (_state command) (values command (reference-probes command)))
    reference-probes cut-command? values))
(def cut-generator
  (model.trace-generator cut-model
    (lambda (_state random _size)
      (let (source (random 16)) (values #t (vector source (bitwise-and source (random 16))))))
    (lambda (command)
      (let ((source (vector-ref command 0)) (delta (vector-ref command 1)))
        (append (map (lambda (next) (vector next (bitwise-and next delta))) (generator.integer-shrinks source))
                (map (lambda (next) (vector source (bitwise-and source next))) (generator.integer-shrinks delta))))) 4))
(def (make-cut-domain steps)
  (property.make-specification
   (lambda (commands) (and (list? commands) (<= (length commands) steps) (andmap cut-command? commands)))
   (lambda (commands) (+ (length commands)
                         (foldl (lambda (command total) (+ total (vector-ref command 0) (vector-ref command 1))) 0 commands)))))
(def cut-domain (make-cut-domain 4))
;;; Keep the historical independent four-step corpus above unchanged. These
;;; state-dependent commands exercise invalidation without discarded inputs.
(def revision-generator
  (model.trace-generator cut-model
    (lambda (state random _size)
      (let* ((source (vector-ref state 0)) (delta (vector-ref state 1))
             (bit (arithmetic-shift 1 (random 4))) (choice (random 5)))
        (values #t
          (case choice
            ((0) (vector source delta))
            ((1) (vector source (bitwise-and source (bitwise-xor delta bit))))
            ((2) (vector (bitwise-ior delta (bitwise-xor source bit)) delta))
            ((3) (vector 0 0))
            (else (let (next (random 16)) (vector next (bitwise-and next (random 16)))))))))
    (lambda (command)
      (let ((source (vector-ref command 0)) (delta (vector-ref command 1)))
        (append (map (lambda (next) (vector next (bitwise-and next delta))) (generator.integer-shrinks source))
                (map (lambda (next) (vector source (bitwise-and source next))) (generator.integer-shrinks delta))))) 8))
(def revision-domain (make-cut-domain 8))
(def revision-codec
  (replay.make-codec '(ascent-empty-bucket (nodes 0 1) (masks 16) (steps 8) (scope version key)) values values))
(def (revision-labels commands)
  (let ((previous (vector 0 0)) (before #f) (labels (cut-labels commands)))
    (for-each
      (lambda (command)
        (def (label! name) (unless (memq name labels) (set! labels (cons name labels))))
        (when (equal? command previous) (label! 'no-op))
        (when (and (not (= (vector-ref command 0) (vector-ref previous 0)))
                   (= (vector-ref command 1) (vector-ref previous 1))) (label! 'source-only-revision))
        (when (and (> (vector-ref previous 0) 0) (= (vector-ref command 0) 0)) (label! 'withdrawal))
        (when (and before (equal? command before) (not (equal? command previous))) (label! 'aba))
        (set! before previous) (set! previous command)) commands)
    labels))
(def (cut-property commands)
  (model.trace-report-matched?
   (model.check-trace cut-model commands
    (lambda (consume)
      (let* ((all (vector [])) (delta (vector [])) (sizes (vector 0)) (dsizes (vector 0))
             (versions (vector 0)) (dversions (vector 0))
             (indexes (gerbil-ascent-make-row-indexes all delta sizes dsizes versions dversions
                        (vector gerbil-ascent-hash-index-provider)))
             (atoms (map (lambda (key) (vector 0 (list (cons 'literal key) '(variable . y))
                                              '(0) [] (list (cons 'literal key)))) '(0 1)))
             (plans (map (lambda (atom)
                           (let* ((heads (list (vector 1 '((variable . y)))))
                                  (body (list (vector 'atom atom)))
                                  (plan (gerbil-ascent-compile-positive-plan heads body)))
                             (vector heads body '(0) 0 (vector 0) plan))) atoms)))
        (row-indexes-plan-rules! indexes plans #t #t)
        (def (observe _state)
          (append-map
           (lambda (lane)
             (append-map
              (lambda (rule)
                (let* ((plan (vector-ref rule 5)) (action (car (vector-ref plan 1)))
                       (frame (make-vector 1 #f)))
                  (def (probe) ((row-indexes-rows indexes) (vector-ref action 0) frame lane (vector-ref action 2)))
                  (list (probe) (probe)))) plans)) '(#f #t)))
        (consume
         (model.make-system #f
          (lambda (state command)
            (let ((source (mask-rows (vector-ref command 0))) (fresh (mask-rows (vector-ref command 1))))
              ;; These are independent cuts: a new delta with unchanged source
              ;; must invalidate the delta certificate, not borrow source age.
              (unless (equal? source (vector-ref all 0))
                (vector-set! all 0 source) (vector-set! sizes 0 (length source))
                (vector-set! versions 0 (+ 1 (vector-ref versions 0))))
              (unless (equal? fresh (vector-ref delta 0))
                (vector-set! delta 0 fresh) (vector-set! dsizes 0 (length fresh))
                (vector-set! dversions 0 (+ 1 (vector-ref dversions 0))))
              (values state (observe state)))) observe)))))))
(def cut-codec
  (replay.make-codec '(ascent-empty-bucket (nodes 0 1) (masks 16) (steps 4) (scope version key)) values values))
(def (cut-labels commands)
  (let ((same-size? #f) (reactivated? #f) (delta-only? #f) (previous 0) (previous-delta 0))
    (for-each (lambda (command)
                (let (source (vector-ref command 0))
                  (when (and (not (= source previous)) (= (length (mask-rows source)) (length (mask-rows previous))))
                    (set! same-size? #t))
                  (when (and (> previous 0) (= (bitwise-and previous 3) 0) (> (bitwise-and source 3) 0))
                    (set! reactivated? #t))
                  (when (and (= source previous) (not (= (vector-ref command 1) previous-delta)))
                    (set! delta-only? #t))
                  (set! previous source) (set! previous-delta (vector-ref command 1)))) commands)
    (filter values
      (list (and same-size? 'equal-size-revision) (and reactivated? 'reactivated-key)
            (and delta-only? 'delta-only-revision)
            (and (ormap (lambda (command)
                          (let ((source (vector-ref command 0)) (delta (vector-ref command 1)))
                            (and (> delta 0)
                                 (or (and (> (bitwise-and source 3) 0) (= (bitwise-and delta 3) 0))
                                     (and (> (bitwise-and source 12) 0) (= (bitwise-and delta 12) 0)))))) commands)
                 'different-lane-buckets)
            (and (ormap (lambda (command) (= (vector-ref command 1) 0)) commands) 'empty-delta)))))
(def ascent-rule-cost-kernel-test
  (test-suite "Native positive-plan cost charge points"
    (test-case "POO state-dependent revision PBT retains shrink and portable replay"
      (let (report (property.check-property revision-generator cut-property revision-domain
                     seed: 20261101 cases: 128 size: 8 shrink-budget: 64
                     policy: (property.make-policy name: 'ascent-empty-bucket-revisions
                               labels: revision-labels
                               required: '((no-op . 1) (source-only-revision . 1) (delta-only-revision . 1)
                                           (withdrawal . 1) (aba . 1) (reactivated-key . 1)
                                           (equal-size-revision . 1) (different-lane-buckets . 1)))))
        (displayln "POO-REVISION-PBT " (property.report-diagnostics report))
        (when (eq? (property.report-status report) 'failed)
          (displayln "POO-REVISION-COUNTEREXAMPLE-BEGIN")
          (replay.write-counterexample report revision-codec (current-output-port))
          (displayln "POO-REVISION-COUNTEREXAMPLE-END"))
        (require-passed report)
        (check-equal? (property.report-accepted report) 128)
        (check-equal? (property.report-discarded report) 0)))
    (test-case "POO model PBT checks source delta versions and lane isolation"
      (let (report (property.check-property cut-generator cut-property cut-domain
                     seed: 20261031 cases: 64 size: 4 shrink-budget: 64
                     policy: (property.make-policy name: 'ascent-empty-bucket
                               labels: cut-labels
                               required: '((equal-size-revision . 1) (reactivated-key . 1)
                                           (delta-only-revision . 1) (different-lane-buckets . 1) (empty-delta . 1)))))
        (displayln "POO-PBT " (property.report-diagnostics report))
        (when (eq? (property.report-status report) 'failed)
          (displayln "POO-PBT-COUNTEREXAMPLE-BEGIN")
          (replay.write-counterexample report cut-codec (current-output-port))
          (displayln "POO-PBT-COUNTEREXAMPLE-END"))
        (require-passed report)
        (check-equal? (property.report-accepted report) 64)
        (check-equal? (property.report-discarded report) 0)))
    (test-case "POO shrunk stale-version counterexample replays after correction"
      ;; Exported by POO from the actual native version-check mutation: 23
      ;; charged shrink proposals, three reductions, exhausted local neighborhood.
      (check-equal?
       (replay.read-counterexample cut-codec
        (open-input-string "#(property-counterexample 1 (ascent-empty-bucket (nodes 0 1) (masks 16) (steps 4) (scope version key)) (#(4 0) #(1 0)))")
        cut-domain cut-property) #t))
    (test-case "independent finite oracle rejects invented support and outside-domain input"
      (check-equal? (finite-domain-closure '(0 1) '((p) (q))
                      '(((p x) (q x)) ((q x) (p x)))) '((p) (q)))
      (check-equal? (finite-domain-closure '(0 1) '((edge (0 1)) (p))
                      '(((p x y) (edge x y)))) '((edge (0 1)) (p (0 1))))
      (check-exception (finite-domain-closure '(0) '((edge (1))) []) error?))
    (test-case "failed candidates, partial matches and multi-head witnesses differ"
      (let ((plan (fixture)) (cost (make-positive-plan-cost)) (emitted []))
        (call-with-positive-plan-cost cost
          (lambda ()
            (gerbil-ascent-run-positive-plan! plan (make-vector 2 #f) -1 inputs
              (lambda (head row) (set! emitted (cons row emitted))))))
        (check-equal? (length emitted) 6)
        (check-equal? (read-count cost 'candidate-rows) 8)
        (check-equal? (read-count cost 'partial-matches) 5)
        (check-equal? (read-count cost 'complete-witnesses) 3)
        (check-equal? (read-count cost 'head-proposals) 6)
        (check-equal? (read-count cost 'repeated-prefixes) 0)
        (check-equal? (read-count cost 'repeated-candidate-visits) 0)
        ;; A fresh frame changes no supporting row or relevant prefix identity.
        (call-with-positive-plan-cost cost
          (lambda () (gerbil-ascent-run-positive-plan! plan (make-vector 2 #f) -1 inputs (lambda args #f))))
        (check-equal? (read-count cost 'repeated-prefixes) 5)
        (check-equal? (read-count cost 'repeated-candidate-visits) 8)
        (check-equal? (read-count cost 'same-plan-prefix-revisits) 5)
        (check-equal? (read-count cost 'same-plan-candidate-revisits) 8)
        (check-equal? (read-count cost 'cross-plan-prefix-revisits) 0)
        (check-equal? (read-count cost 'same-plan-complete-revisits) 3)
        ;; An independently compiled equal body is a different plan owner.
        (call-with-positive-plan-cost cost
          (lambda () (gerbil-ascent-run-positive-plan! (fixture) (make-vector 2 #f) -1 inputs (lambda args #f))))
        (check-equal? (read-count cost 'repeated-prefixes) 10)
        (check-equal? (read-count cost 'repeated-candidate-visits) 16)
        (check-equal? (read-count cost 'cross-plan-prefix-revisits) 5)
        (check-equal? (read-count cost 'cross-plan-candidate-revisits) 8)
        (check-equal? (read-count cost 'repeated-complete-witnesses) 6)
        (check-equal? (read-count cost 'cross-plan-complete-revisits) 3)))
    (test-case "nested native traversal retains its own plan attribution"
      (def (one-atom-plan)
        (gerbil-ascent-compile-positive-plan
         (list (vector 2 '((variable . x))))
         (list (vector 'atom (vector 0 '((variable . x)) [] [] [])))))
      (let ((outer (one-atom-plan)) (inner (one-atom-plan))
            (cost (make-positive-plan-cost)) (first? #t))
        (call-with-positive-plan-cost cost
          (lambda ()
            (gerbil-ascent-run-positive-plan! outer (make-vector 1 #f) -1 inputs
              (lambda args
                (when first?
                  (set! first? #f)
                  (gerbil-ascent-run-positive-plan! inner (make-vector 1 #f) -1 inputs
                    (lambda args #f)))))))
        (check-equal? (read-count cost 'cross-plan-prefix-revisits) 2)
        (check-equal? (read-count cost 'cross-plan-candidate-revisits) 2)
        (check-equal? (read-count cost 'same-plan-prefix-revisits) 0)
        (check-equal? (read-count cost 'same-plan-candidate-revisits) 0)))
    (test-case "unrecorded repeated prefixes are unknown rather than zero"
      (let (cost (make-positive-plan-cost #f))
        (call-with-positive-plan-cost cost
          (lambda () (gerbil-ascent-run-positive-plan! (fixture) (make-vector 2 #f) -1 inputs (lambda args #f))))
        (check-equal? (read-count cost 'repeated-prefixes) #f)
        (check-equal? (read-count cost 'repeated-candidate-visits) #f)
        (check-equal? (read-count cost 'same-plan-prefix-revisits) #f)
        (check-equal? (read-count cost 'cross-plan-candidate-revisits) #f)
        (check-equal? (read-count cost 'same-plan-complete-revisits) #f)
        (check-equal? (read-count cost 'candidate-rows) 8)))
    (test-case "visit attribution is optional detached and preserves unknown repeats"
      (check-equal? (positive-plan-cost-visits (make-positive-plan-cost)) #f)
      (for-each
       (lambda (record-prefixes?)
         (let (cost (make-positive-plan-cost record-prefixes? #t))
           (call-with-positive-plan-cost cost
             (lambda () (gerbil-ascent-run-positive-plan! (fixture) (make-vector 2 #f) -1 inputs
                          (lambda args #f) #f #f #f '(0 1 7))))
           (let (visits (positive-plan-cost-visits cost))
             (check-equal? (length visits) 8)
             (check-equal? (length (filter (lambda (visit) (list-ref visit 3)) visits)) 5)
             (unless record-prefixes?
               (check-equal? (andmap (lambda (visit) (eq? (list-ref visit 4) 'unrecorded)) visits) #t)
               (check-equal? (read-count cost 'same-plan-candidate-revisits) #f)
               (check-equal? (read-count cost 'index-build-input-rows) 0))
             (set-car! (caar visits) 'changed-by-reader)
             (check-equal? (caar (positive-plan-cost-visits cost)) '(0 1 7))))) '(#f #t)))
    (test-case "small exact bucket reuse invalidates on equal-size replacement and empty selection"
      (let* ((atom (vector 0 '((literal . 0) (variable . y)) '(0) [] '((literal . 0))))
             (body (list (vector 'atom atom))) (heads (list (vector 1 '((variable . y)))))
             (plan (gerbil-ascent-compile-positive-plan heads body))
             (action (car (vector-ref plan 1)))
             (all (vector '((0 10) (1 11)))) (delta (vector []))
             (sizes (vector 2)) (versions (vector 0))
             (indexes (gerbil-ascent-make-row-indexes all delta sizes (vector 0) versions (vector 0)
                        (vector gerbil-ascent-hash-index-provider)))
             (cost (make-positive-plan-cost #f)) (frame (make-vector 1 #f)))
        (row-indexes-plan-rules! indexes (list (vector heads body '(0) 0 (vector 0) plan)) #t)
        (def (probe)
          ((row-indexes-rows indexes) atom frame #f (vector-ref action 2)))
        (call-with-positive-plan-cost cost
          (lambda ()
            (let (old (probe))
              (check-equal? old '((0 10)))
              (check-equal? (probe) old)
              (check-equal? (read-count cost 'index-build-input-rows) 2)
              (vector-set! all 0 '((0 20) (1 21)))
              (vector-set! versions 0 1)
              (check-equal? (probe) '((0 20)))
              (check-equal? old '((0 10)))
              (vector-set! all 0 '((1 21))) (vector-set! sizes 0 1) (vector-set! versions 0 2)
              (check-equal? (probe) [])
              (vector-set! all 0 '((0 10) (1 11))) (vector-set! sizes 0 2) (vector-set! versions 0 3)
              (check-equal? (probe) '((0 10)))
              (check-equal? (read-count cost 'index-build-input-rows) 7)
              (check-equal? (read-count cost 'physical-index-probes) 5)
              ;; The physical index is selection, not deduplication: retain
              ;; both equal rows and their order within the matching bucket.
              (vector-set! all 0 '((0 20) (0 10) (0 20) (1 11)))
              (vector-set! sizes 0 4) (vector-set! versions 0 4)
              (check-equal? (probe) '((0 20) (0 10) (0 20)))
              (check-equal? (read-count cost 'index-build-input-rows) 11)
              (check-equal? (read-count cost 'physical-index-probes) 6))))))
    (test-case "first-fresh partition removes duplicate pivots but keeps distinct supports"
      (let* ((plan (gerbil-ascent-compile-positive-plan
                    (list (vector 1 '((variable . x) (variable . y))))
                    (list (vector 'atom (vector 0 '((variable . x)) [] [] []))
                          (vector 'atom (vector 0 '((variable . y)) [] [] [])))))
             (exact []) (overlapping []))
        (def (rows atom frame delta? terms) (if delta? '((0)) '((0) (1))))
        (def (old atom frame terms checkpoint!) '((1)))
        (for-each
         (lambda (pivot)
           (gerbil-ascent-run-positive-plan! plan (make-vector 2 #f) pivot rows
             (lambda (head row) (set! exact (cons row exact))) #f #f old)
           (gerbil-ascent-run-positive-plan! plan (make-vector 2 #f) pivot rows
             (lambda (head row) (set! overlapping (cons row overlapping))))) '(0 1))
        (check-equal? (length exact) 3)
        (check-equal? (andmap (lambda (row) (and (member row exact) #t)) '((0 0) (0 1) (1 0))) #t)
        (check-equal? (length (filter (lambda (row) (= (car row) 0)) exact)) 2)
        ;; Counterexample to deduplicating by head or claiming overlapping
        ;; scheduling duplicates are distinct semantic supporting witnesses.
        (check-equal? (length overlapping) 4)
        (check-equal? (length (filter (lambda (row) (equal? row '(0 0))) overlapping)) 2)))
    (test-case "interruption preserves real work but emits no completed witness"
      (let ((cost (make-positive-plan-cost)) (emitted 0))
        (check-exception
          (call-with-positive-plan-cost cost
            (lambda ()
              (gerbil-ascent-run-positive-plan! (fixture) (make-vector 2 #f) -1 inputs
                (lambda args (set! emitted (+ emitted 1)))
                (lambda () (error "diagnostic interrupted at the first real candidate"))))) error?)
        (check-equal? emitted 0)
        (check-equal? (read-count cost 'candidate-rows) 1)
        (check-equal? (read-count cost 'partial-matches) 1)
        (check-equal? (read-count cost 'complete-witnesses) 0)))
    (test-case "unsupported callback plans refuse measurement before invocation"
      (let* ((calls 0)
             (plan (gerbil-ascent-compile-positive-plan
                     [ (vector 0 []) ]
                     [ (vector 'guard [] (lambda () (set! calls (+ calls 1)) #t)) ])))
        (check-exception
          (call-with-positive-plan-cost (make-positive-plan-cost)
            (lambda () (gerbil-ascent-run-positive-plan! plan [] -1 inputs (lambda args #f)))) error?)
        (check-equal? calls 0)))))
