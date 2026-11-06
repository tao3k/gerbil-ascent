;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/core/positive-plan current-positive-prefix-budget))
(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :std/list/list append-map)
        (prefix-in :clan/poo/testing/property support-property.)
        (prefix-in :clan/poo/testing/property/generator support-generator.)
        (prefix-in :clan/poo/testing/property/model support-model.)
        (prefix-in :clan/poo/testing/property/replay support-replay.)
        (only-in :clan/poo/testing/property/test require-passed)
        (only-in :gerbil-ascent/candidate/provenance positive-proof-nodes positive-proof-snapshot-generation
                 proof-node-id proof-node-relation proof-node-row)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/checked-program reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/provenance-graph
                 candidate-positive-provenance candidate-verify-positive-provenance
                 positive-provenance-status positive-provenance-alternatives
                 candidate-open-provenance-maintenance provenance-maintenance-rows
                 candidate-provenance-withdraw! candidate-provenance-preview-withdraw
                 candidate-provenance-compact provenance-maintenance-size candidate-provenance-heights
                 provenance-maintenance-alternatives))
(import (rename-in (only-in :gerbil-ascent/t/performance/provenance-index/reference
                           candidate-positive-provenance positive-provenance-status
                           positive-provenance-alternatives positive-provenance-witness)
                   (candidate-positive-provenance reference-provenance)
                   (positive-provenance-status reference-status)
                   (positive-provenance-alternatives reference-alternatives)
                   (positive-provenance-witness reference-witness))
        (only-in :gerbil-ascent/candidate/provenance-graph positive-provenance-witness))
(import (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-admit relational-solve relational-query-name
                 relational-open-program-session relational-program-query relational-program-session-run
                 relational-program-append-source! relational-program-transaction!))
(import (rename-in (only-in :gerbil-ascent/t/performance/provenance-maintenance/reference
                           candidate-positive-provenance candidate-open-provenance-maintenance
                           candidate-provenance-withdraw! provenance-maintenance-rows)
                   (candidate-positive-provenance prior-graph)
                   (candidate-open-provenance-maintenance prior-open)
                   (candidate-provenance-withdraw! prior-withdraw!)
                   (provenance-maintenance-rows prior-rows)))

(import (only-in :gerbil-ascent/candidate/provenance-maintenance candidate-make-provenance-maintenance))

(def corpus-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def (edges-for-mask mask)
  (filter-map (lambda (edge position)
                (and (odd? (quotient mask (expt 2 position))) edge))
              corpus-edges '(0 1 2 3 4 5)))

;;; Independent matrix closure, not a relational/provenance evaluator.
(def (matrix-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each (lambda (edge)
                (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t)) edges)
    (for-each
     (lambda (k)
       (for-each
        (lambda (i)
          (for-each (lambda (j)
                      (when (and (vector-ref matrix (+ (* 3 i) k))
                                 (vector-ref matrix (+ (* 3 k) j)))
                        (vector-set! matrix (+ (* 3 i) j) #t))) '(0 1 2)))
        '(0 1 2))) '(0 1 2))
    (filter-map (lambda (position)
                  (and (vector-ref matrix position)
                       (list (quotient position 3) (modulo position 3)))) (iota 9))))

(def (execution-paths edges)
  (relational-query-name
   (relational-solve
    (relational-admit
     (relational-program
      (relation edge (from to) edges)
      (relation path (from to) '())
      (rule (path ?x ?y) (edge ?x ?y))
      (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
      (limits 16 64 128)))) 'path))

(def (check-row-set actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))

;;; Independent finite support oracle: source occurrences and three fixed rule
;;; occurrences. The two equal user labels must not identify the same rule.
(def support-occurrences '((left (0)) (left (1)) (left (0)) (right (0)) (right (1))))
(def (support-ids mask)
  (filter (lambda (id) (not (zero? (bitwise-and mask (arithmetic-shift 1 id))))) (iota 5)))
(def (support-source mask name)
  (filter-map (lambda (id) (let (entry (list-ref support-occurrences id))
                            (and (eq? (car entry) name) (cadr entry)))) (support-ids mask)))
(def (support-sort edges)
  (def (text value) (with-output-to-string (lambda () (write value))))
  (list-sort (lambda (a b) (string<? (text a) (text b))) edges))
(def (support-reference state)
  (let* ((mask (car state)) (epoch (cadr state))
         (left (support-source mask 'left)) (right (support-source mask 'right))
         (sources (map (lambda (id)
                         (let (entry (list-ref support-occurrences id))
                           (list entry 'source (list epoch id) []))) (support-ids mask)))
         (rules
          (append-map
           (lambda (position)
             (filter-map
              (lambda (x)
                (and (member (list x) left)
                     (or (= position 2) (member (list x) right))
                     (list '(out (0)) 'rule (list position (if (= position 2) 11 10))
                       (list (list 'left (list x)) (list (if (= position 2) 'left 'right) (list x)))))) '(0 1)))
           '(0 1 2))))
    (list (if (null? left) [] '((0))) (support-sort (append sources rules)))))
(def (support-next state mask)
  (list mask (+ (cadr state) (if (= (bitwise-and mask (car state)) mask) 0 1))))
(def support-model
  (support-model.make-model (lambda () '(31 0)) (lambda (_state _command) #t)
    (lambda (state command) (let (next (support-next state command)) (values next (support-reference next))))
    support-reference (lambda (mask) (and (exact-integer? mask) (<= 0 mask 31))) values))
(def support-generator
  (support-model.trace-generator support-model
    (lambda (state random _size)
      (let ((mask (car state)) (bit (arithmetic-shift 1 (random 5))))
        (values #t (case (random 4)
          ((0) mask) ((1) (bitwise-and mask (bitwise-not bit)))
          ((2) (bitwise-ior mask bit)) (else (random 32))))))
    support-generator.integer-shrinks 6))
(def support-domain
  (support-property.make-specification
    (lambda (commands) (and (list? commands) (<= (length commands) 6)
                           (andmap (lambda (n) (and (exact-integer? n) (<= 0 n 31))) commands)))
    (lambda (commands) (+ (length commands) (foldl + 0 commands)))))
(def support-codec
  (support-replay.make-codec '(ascent-grounded-support (occurrences 5) (steps 6) (scope generation)) values values))
(def (support-labels commands)
  (let ((state '(31 0)) (prior #f) (labels []))
    (def (label! name) (unless (memq name labels) (set! labels (cons name labels))))
    (for-each (lambda (mask)
      (let ((before (car state)) (next (support-next state mask)))
        (when (= mask before) (label! 'no-op))
        (when (< (length (support-ids mask)) (length (support-ids before))) (label! 'withdrawal))
        (when (> (cadr next) (cadr state)) (label! 'rebuild))
        (when (and (not (= mask before)) (= (bitwise-and mask before) before)) (label! 'delta-append))
        (when (and prior (= mask prior) (not (= mask before))) (label! 'aba))
        (when (= (bitwise-and mask 5) 4) (label! 'duplicate-survivor))
        (set! prior before) (set! state next))) commands)
    labels))
(def (support-program mask)
  (let ((left (support-source mask 'left)) (right (support-source mask 'right)))
    (relational-program
      (relation left (x) left) (relation right (x) right) (relation out (x))
      (rule (out 0) (left ?x) (right ?x))
      (rule (out 0) (left ?x) (right ?x))
      (rule (out 0) (left ?x) (left ?x))
      (limits 16 64 128))))
(def (support-spec)
  (make-reasoning-candidate '((out . 1)) []
    (list (vector '(out 0) '((left ?x) (right ?x)) 10)
          (vector '(out 0) '((left ?x) (right ?x)) 10)
          (vector '(out 0) '((left ?x) (left ?x)) 11))
    (vector '(out ?x) 12) '(16 64 128)))
(def (support-observation graph maintenance basis)
          (let* ((nodes (positive-proof-nodes (positive-provenance-witness graph)))
                 (by-id (make-hash-table-eqv))
                 (epoch (positive-proof-snapshot-generation (positive-provenance-witness graph))))
            (for-each (lambda (node) (hash-put! by-id (proof-node-id node)
                                      (list (proof-node-relation node) (proof-node-row node)))) nodes)
            (def (token label)
              (let* ((name (car label)) (position (cadr label))
                     (ids (filter (lambda (id) (eq? (car (list-ref support-occurrences id)) name)) (support-ids basis))))
                (list epoch (list-ref ids (- position 1)))))
            (let-values (((edges work) (provenance-maintenance-alternatives maintenance)))
              (let (normalized
                    (map (lambda (edge)
                      (list (hash-ref by-id (car edge)) (cadr edge)
                        (if (eq? (cadr edge) 'source) (token (caddr edge)) (caddr edge))
                        (map (lambda (id) (hash-ref by-id id)) (cadddr edge)))) edges))
                (list (provenance-maintenance-rows maintenance) (support-sort normalized))))))

(def (support-trace commands)
  (support-model.trace-report-matched?
   (support-model.check-trace support-model commands
    (lambda (consume)
      (let* ((state '(31 0)) (basis 31) (graph #f) (maintenance #f) (snapshot #f)
             (spec (support-spec)) (session (relational-open-program-session (support-program 31))))
        (def (native) (relational-program-query (relational-program-session-run session) 'out))
        (def (rebuild!)
          (let* ((epoch (cadr state)) (mask (car state))
                 (next-snapshot (reasoning-source-snapshot 'support-scope epoch
                    (list (list 'left 1 (support-source mask 'left)) (list 'right 1 (support-source mask 'right)))))
                 (rows (native))
                 (next-graph (candidate-positive-provenance next-snapshot spec 'supports 'complete rows 2048)))
            (when graph
              (unless (not (candidate-verify-positive-provenance next-snapshot spec 'supports 'complete rows graph 2048))
                (error "old-generation graph accepted")))
            (set! basis mask) (set! snapshot next-snapshot) (set! graph next-graph)
            (set! maintenance (candidate-open-provenance-maintenance snapshot spec 'supports 'complete rows graph 2048))))
        (def (observe _state)
          (let (observation (support-observation graph maintenance basis))
            (unless (equal? (car observation) (native)) (error "retained graph rows differ from native DSL"))
            observation))
        (rebuild!)
        (consume
         (support-model.make-system #f
          (lambda (_state mask)
            (let* ((before (car state)) (next (support-next state mask))
                   (removed (filter (lambda (id) (not (memv id (support-ids mask)))) (support-ids before))))
              (if (and (not (= mask before)) (= (bitwise-and mask before) before))
                (for-each (lambda (id)
                            (let (entry (list-ref support-occurrences id))
                              (relational-program-append-source! session (car entry) (cadr entry))))
                          (filter (lambda (id) (not (memv id (support-ids before)))) (support-ids mask)))
                (relational-program-transaction! session
                  (list (cons 'left (support-source mask 'left)) (cons 'right (support-source mask 'right)))))
              (if (= (cadr next) (cadr state))
                (let ((selectors
                       (map (lambda (id)
                         (let* ((name (car (list-ref support-occurrences id)))
                                (ids (filter (lambda (i) (eq? (car (list-ref support-occurrences i)) name))
                                             (support-ids basis))))
                           (list name (let find ((rest ids) (position 1))
                             (if (= (car rest) id) position (find (cdr rest) (+ position 1))))))) removed)))
                  (candidate-provenance-withdraw! maintenance selectors))
                (begin (set! state next) (rebuild!)))
              (set! state next) (values #f (observe #f)))) observe)))))))

(export scheme-provenance-graph-test scheme-minimum-height-test)

(def (recursive-provenance-spec)
  (make-reasoning-candidate
   '((p . 1)) []
   (list (vector '(p ?x) '((s ?x)) 10)
         (vector '(p ?x) '((p ?x)) 11))
   (vector '(p ?x) 12) '(8 16 32)))

(def scheme-minimum-height-test
  (test-suite "Minimum grounded proof heights"
    (test-case "height relaxation improves a previously discovered longer proof"
      (let* ((snapshot (reasoning-source-snapshot 'height-relax 0 '((s 1 ((1))))))
             (spec (make-reasoning-candidate '((a . 1) (b . 1) (p . 1)) []
                     (list (vector '(a ?x) '((s ?x)) 10)
                           (vector '(b ?x) '((a ?x)) 11)
                           (vector '(p ?x) '((b ?x)) 12)
                           (vector '(p ?x) '((s ?x)) 13)
                           (vector '(p ?x) '((p ?x)) 14))
                     (vector '(p ?x) 15) '(8 32 64)))
             (graph (candidate-positive-provenance snapshot spec 'program 'complete '((1)) 1024))
             ;; Sort already verified ground alternatives to discover height 3
             ;; before the height 1 alternative in the same relaxation pass.
             (edges (list-sort (lambda (a b)
                                (< (if (eq? (cadr a) 'source) -1 (car (caddr a)))
                                   (if (eq? (cadr b) 'source) -1 (car (caddr b)))))
                              (positive-provenance-alternatives graph)))
             (state (candidate-make-provenance-maintenance (positive-provenance-witness graph) edges)))
        (let-values (((heights work) (candidate-provenance-heights state)))
          (check-equal? heights '(((1) 1)))
          (check-exception (candidate-provenance-heights state (- work 1)) true)
          (check-equal? (provenance-maintenance-rows state) '((1)))
          (let-values (((exact measured) (candidate-provenance-heights state work)))
            (check-equal? exact heights) (check-equal? measured work)))
        (candidate-provenance-withdraw! state '((s 1)))
        (let-values (((heights _) (candidate-provenance-heights state)))
          (check-equal? heights []))))
  ))

(def scheme-provenance-graph-test
  (test-suite "Complete grounded provenance and deletion"
    (test-case "factorized DAG source revisions preserve exact four-premise rule alternatives"
      (def (program left right)
        (relational-program
          (relation left (a b) left) (relation right (a b) right) (relation out (x))
          (rule (out 0) (left ?a ?b) (right ?b ?c) (left ?c ?d) (right ?d ?e))
          (rule (out 0) (left ?u ?v) (right ?v ?w) (left ?w ?x) (right ?x ?y))
          (limits 128 256 512)))
      (def spec
        (make-reasoning-candidate '((out . 1)) []
          (list (vector '(out 0) '((left ?a ?b) (right ?b ?c) (left ?c ?d) (right ?d ?e)) 10)
                (vector '(out 0) '((left ?u ?v) (right ?v ?w) (left ?w ?x) (right ?x ?y)) 10))
          (vector '(out ?x) 12) '(128 256 512)))
      (def (flat f xs) (foldr (lambda (x tail) (append (f x) tail)) [] xs))
      (def (expected left right)
        (append
          (apply append (map (lambda (name rows)
            (map (lambda (row position) (list (list name row) 'source (list name position) []))
                 rows (iota (length rows) 1))) '(left right) (list left right)))
          (flat (lambda (position)
            (flat (lambda (a) (flat (lambda (b) (flat (lambda (c) (flat (lambda (d)
              (if (and (= (cadr a) (car b)) (= (cadr b) (car c)) (= (cadr c) (car d)))
                (list (list '(out (0)) 'rule (list position 10)
                  (list (list 'left a) (list 'right b) (list 'left c) (list 'right d)))) [])) right)) left)) right)) left)) '(0 1))))
      (def (normalize graph)
        (let (by-id (make-hash-table-eqv))
          (for-each (lambda (node) (hash-put! by-id (proof-node-id node)
            (list (proof-node-relation node) (proof-node-row node))))
            (positive-proof-nodes (positive-provenance-witness graph)))
          (support-sort (map (lambda (edge)
            (list (hash-ref by-id (car edge)) (cadr edge) (caddr edge)
                  (map (lambda (id) (hash-ref by-id id)) (cadddr edge))))
            (positive-provenance-alternatives graph)))))
      (let* ((left0 '((0 0) (0 1))) (right0 '((0 0) (1 1)))
             (session (parameterize ((current-positive-prefix-budget 4096))
                        (relational-open-program-session (program left0 right0))))
             (sibling (parameterize ((current-positive-prefix-budget 4096))
                        (relational-open-program-session (program left0 right0))))
             (held (relational-program-session-run sibling)) (old-graph #f) (generation 0))
        (for-each (lambda (cut)
          (let* ((left (car cut)) (right (cadr cut)))
            (relational-program-transaction! session (list (cons 'left left) (cons 'right right)))
            (let* ((rows (relational-program-query (relational-program-session-run session) 'out))
                   (snapshot (reasoning-source-snapshot 'dag-support generation
                               (list (list 'left 2 left) (list 'right 2 right))))
                   (graph (candidate-positive-provenance snapshot spec 'dag 'complete rows 32768 4096)))
              (check-equal? (positive-provenance-status graph) 'complete)
              (check-equal? (normalize graph) (support-sort (expected left right)))
              (check-equal? (candidate-verify-positive-provenance snapshot spec 'dag 'complete rows graph 32768 4096) #t)
              (when old-graph
                (check-equal? (candidate-verify-positive-provenance snapshot spec 'dag 'complete rows old-graph 32768 4096) #f))
              (set! old-graph graph) (set! generation (+ generation 1)))
            (check-equal? (relational-program-query held 'out) '((0)))
            (check-equal? (relational-program-query (relational-program-session-run sibling) 'out) '((0)))))
          (list (list left0 right0) (list '((0 0) (0 1) (1 0)) right0)
                (list '((0 0) (0 1) (1 0)) '((0 1) (1 0))) (list left0 right0)))))
    (test-case "sibling source-cut previews preserve their shared verified parent"
      (let* ((snapshot (reasoning-source-snapshot 'support-branches 0
                        (list (list 'left 1 (support-source 31 'left)) (list 'right 1 (support-source 31 'right)))))
             (spec (support-spec))
             (graph (candidate-positive-provenance snapshot spec 'supports 'complete '((0)) 2048))
             (parent (candidate-open-provenance-maintenance snapshot spec 'supports 'complete '((0)) graph 2048)))
        (let-values (((a a-rows a-work) (candidate-provenance-preview-withdraw parent '((left 1) (left 3))))
                     ((b b-rows b-work) (candidate-provenance-preview-withdraw parent '((left 2)))))
          (check-equal? (support-observation graph parent 31) (support-reference '(31 0)))
          (check-equal? (support-observation graph a 31) (support-reference '(26 0)))
          (check-equal? (support-observation graph b 31) (support-reference '(29 0)))
          (candidate-provenance-withdraw! a '((left 2)))
          (let-values (((compact work) (candidate-provenance-compact a)))
            (check-equal? (support-observation graph compact 31) (support-reference '(24 0))))
          (check-equal? (support-observation graph parent 31) (support-reference '(31 0)))
          (check-equal? (support-observation graph b 31) (support-reference '(29 0))))))
    (test-case "actual alternatives survive same-head cuts append and restored generations"
      (check-equal? (support-trace '(30 26 24 25 0 31)) #t)
      (check-equal? (support-trace '(30 31 30 31 0 31)) #t))
    (test-case "POO graph revision PBT compares exact grounded alternatives with a finite oracle"
      (let (report (support-property.check-property support-generator support-trace support-domain
                     seed: 20261102 cases: 64 size: 6 shrink-budget: 64
                     policy: (support-property.make-policy name: 'ascent-grounded-support-revisions
                               labels: support-labels required: '((withdrawal . 1) (rebuild . 1)
                                 (delta-append . 1) (aba . 1) (duplicate-survivor . 1)))))
        (displayln "POO-GRAPH-SUPPORT-PBT " (support-property.report-diagnostics report))
        (when (eq? (support-property.report-status report) 'failed)
          (support-replay.write-counterexample report support-codec (current-output-port)))
        (require-passed report)
        (check-equal? (support-property.report-accepted report) 64)
        (check-equal? (support-property.report-discarded report) 0)))
    (test-case "current alternatives are detached bounded and agree before and after compaction"
      (let* ((snapshot (reasoning-source-snapshot 'support-read 0
                        (list (list 'left 1 (support-source 31 'left)) (list 'right 1 (support-source 31 'right)))))
             (spec (support-spec))
             (graph (candidate-positive-provenance snapshot spec 'supports 'complete '((0)) 2048))
             (state (candidate-open-provenance-maintenance snapshot spec 'supports 'complete '((0)) graph 2048)))
        (let-values (((edges work) (provenance-maintenance-alternatives state)))
          (check-equal? (length edges) 11)
          ;; A readable projection is not an authenticated full certificate.
          (check-equal? (candidate-verify-positive-provenance snapshot spec 'supports 'complete '((0)) edges 2048) #f)
          (for-each
           (lambda (generation)
             (let (revised (reasoning-source-snapshot 'support-read generation
                             (list (list 'left 1 (support-source 30 'left)) (list 'right 1 (support-source 30 'right)))))
               ;; The head is unchanged, but source content and/or epoch differ.
               (check-equal? (candidate-verify-positive-provenance revised spec 'supports 'complete '((0)) graph 2048) #f)))
           '(0 1))
          (for-each (lambda (budget)
                      (check-exception (provenance-maintenance-alternatives state budget) true)) (iota (- work 1) 1))
          (set-car! (caddr (car edges)) 'caller-mutation)
          (let-values (((again charged) (provenance-maintenance-alternatives state work)))
            (check-equal? again (positive-provenance-alternatives graph))
            (check-equal? charged work)))
        (candidate-provenance-withdraw! state '((left 1)))
        (let-values (((edges _) (provenance-maintenance-alternatives state))
                     ((compacted work) (candidate-provenance-compact state)))
          (let-values (((after _) (provenance-maintenance-alternatives compacted)))
            (check-equal? after edges)
            (check-equal? (length edges) 10)))))
    (test-case "withdrawal previews stage independent cuts before owner publication"
      (let* ((snapshot (reasoning-source-snapshot 'preview 1 '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance snapshot spec 'program 'complete '((1)) 64))
             (original (candidate-open-provenance-maintenance snapshot spec 'program 'complete '((1)) graph 64)))
        (let-values (((next rows work) (candidate-provenance-preview-withdraw original '((s 1)))))
          (check-equal? rows '((1)))
          (check-equal? (provenance-maintenance-rows original) '((1)))
          (let-values (((empty empty-rows _) (candidate-provenance-preview-withdraw next '((s 2)))))
            (check-equal? empty-rows [])
            (check-equal? (provenance-maintenance-rows empty) [])
            (check-equal? (provenance-maintenance-rows next) '((1)))
            (check-equal? (provenance-maintenance-rows original) '((1))))
          (set-car! (car rows) 9)
          (check-equal? (provenance-maintenance-rows next) '((1)))
          (check-exception (candidate-provenance-preview-withdraw next '((s 2)) 1) true)
          (check-equal? (provenance-maintenance-rows next) '((1))))
        (check-exception (candidate-provenance-preview-withdraw original '((unknown 1))) true)
        ;; Discarded previews have not accumulated source removals in original.
        (let-values (((rows _) (candidate-provenance-withdraw! original '((s 2)))))
          (check-equal? rows '((1))))))
    (test-case "complete withdrawal work bounds preserve reference rows and rollback"
      (let* ((snapshot (reasoning-source-snapshot 'budget-parity 1 '((s 1 ((1) (1) (2))))))
             (spec (recursive-provenance-spec))
             (rows '((1) (2)))
             (old-graph (prior-graph snapshot spec 'program 'complete rows 128))
             (new-graph (candidate-positive-provenance snapshot spec 'program 'complete rows 128)))
        (def (fresh)
          (candidate-open-provenance-maintenance snapshot spec 'program 'complete rows new-graph 128))
        (for-each
         (lambda (selectors)
           (let-values (((expected old-work)
                         (prior-withdraw! (prior-open snapshot spec 'program 'complete rows old-graph 128) selectors))
                        ((actual work) (candidate-provenance-withdraw! (fresh) selectors)))
             (check-equal? actual expected)
             (check-equal? (> work old-work) #t)
             (for-each
              (lambda (budget)
                (let (state (fresh))
                  (if (< budget work)
                    (begin
                      (check-exception (candidate-provenance-withdraw! state selectors budget) true)
                      (check-equal? (provenance-maintenance-rows state) rows)
                      ;; Failure even at the last root visit has not retired s1.
                      (let-values (((remaining _) (candidate-provenance-withdraw! state '((s 2)))))
                        (check-equal? remaining rows)))
                    (let-values (((result measured) (candidate-provenance-withdraw! state selectors budget)))
                      (check-equal? result expected)
                      (check-equal? measured work))))) (iota 64 1))))
         '(((s 1)) ((s 2)) ((s 3)) ()))))
    (test-case "wide grounded conjunctions charge every inspected premise"
      (let* ((snapshot (reasoning-source-snapshot 'wide-budget 1 '((s 1 ((1))) (t 1 ((1))))))
             (body (append (make-list 24 '(t ?x)) '((s ?x))))
             (spec (make-reasoning-candidate '((p . 1)) []
                     (list (vector '(p ?x) body 10)) (vector '(p ?x) 11) '(8 64 128)))
             (graph (candidate-positive-provenance snapshot spec 'program 'complete '((1)) 1024))
             (state (candidate-open-provenance-maintenance snapshot spec 'program 'complete '((1)) graph 1024)))
        ;; An edge-only budget previously admitted all twenty-five inspections.
        (check-exception (candidate-provenance-withdraw! state '((s 1)) 16) true)
        (check-equal? (provenance-maintenance-rows state) '((1)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 1)))))
          (check-equal? rows [])
          (check-equal? (> work 25) #t))))
    (test-case "published withdrawals and query rows own their pair spines"
      (let* ((snapshot (reasoning-source-snapshot 'owned-withdrawal 1 '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance snapshot spec 'program 'complete '((1)) 64))
             (state (candidate-open-provenance-maintenance snapshot spec 'program 'complete '((1)) graph 64))
             (selectors (list (list 's 1))))
        (let-values (((rows work) (candidate-provenance-withdraw! state selectors)))
          (set-car! (car rows) 99))
        (set-car! (cdr (car selectors)) 2)
        (check-equal? (provenance-maintenance-rows state) '((1)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 2)))))
          (check-equal? rows []))))
    (test-case "indexed enumeration preserves order and exact budget boundaries"
      (let* ((snapshot (reasoning-source-snapshot 'ordered-index 1
                         '((s 1 ((#f) (#f) (#\a) (#\b)))
                           (unused 1 ((7) (8) (9))))))
             (spec (recursive-provenance-spec)))
        (for-each
         (lambda (budget)
           (for-each
            (lambda (cap)
              (let ((old (reference-provenance snapshot spec 'program 'complete
                                              '((#f) (#\a) (#\b)) budget cap))
                    (new (candidate-positive-provenance snapshot spec 'program 'complete
                                                        '((#f) (#\a) (#\b)) budget cap)))
                (check-equal? (positive-provenance-status new) (reference-status old))
                (check-equal? (positive-provenance-alternatives new)
                              (reference-alternatives old))
                (check-equal? (positive-provenance-witness new) (reference-witness old))))
            '(1 7 8 11 12 13 14 16 32)))
         '(1 2 4 8 16 32 64 128))
        (let (graph (candidate-positive-provenance snapshot spec 'program 'complete
                                                 '((#f) (#\a) (#\b)) 128 13))
          (check-equal? (positive-provenance-status graph) 'complete)
          (check-equal? (length (positive-provenance-alternatives graph)) 13)
          (check-equal?
           (map caddr (filter (lambda (edge) (eq? (cadr edge) 'source))
                              (positive-provenance-alternatives graph)))
           '((s 1) (s 2) (s 3) (s 4) (unused 1) (unused 2) (unused 3))))))
    (test-case "recursive provenance retains every source and cyclic alternative"
      (let* ((snapshot (reasoning-source-snapshot 'complete-graph 1
                                                  '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64)))
        (check-equal? (positive-provenance-status graph) 'complete)
        (check-equal? (length (positive-provenance-alternatives graph)) 4)
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'program 'complete '((1)) graph 64) #t)
        (check-equal? (member '(1 rule (1 11) (1))
                             (positive-provenance-alternatives graph))
                      '((1 rule (1 11) (1))))))
    (test-case "a recursive cycle without a founded source proves no row"
      (let* ((snapshot (reasoning-source-snapshot 'empty-cycle 1 '((s 1 ()))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete [] 64)))
        (check-equal? (positive-provenance-status graph) 'complete)
        (check-equal? (positive-provenance-alternatives graph) [])
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'program 'complete [] graph 64) #t)))
    (test-case "complete provenance cannot omit an alternative or exceed its cap"
      (let* ((snapshot (reasoning-source-snapshot 'tamper-graph 1 '((s 1 ((1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64))
             (bounded (candidate-positive-provenance
                       snapshot spec 'program 'complete '((1)) 64 2)))
        (check-equal? (positive-provenance-status bounded) 'bounded)
        (check-equal? (positive-provenance-alternatives bounded) [])
        (set-cdr! (positive-provenance-alternatives graph) [])
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'program 'complete '((1)) graph 64) #f)
        (check-equal? (candidate-verify-positive-provenance
                      snapshot spec 'different 'complete '((1)) graph 64) #f)))
    (test-case "grounded DRed restores alternate support and removes the last cyclic support"
      (let* ((snapshot (reasoning-source-snapshot 'deletion 1 '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64))
             (state (candidate-open-provenance-maintenance
                     snapshot spec 'program 'complete '((1)) graph 64)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 1)))))
          (check-equal? rows '((1)))
          (check-equal? (> work 0) #t)
          (let-values (((edges inspected) (provenance-maintenance-alternatives state)))
            (check-equal? (length edges) 3)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 2)))))
          (check-equal? rows [])
          (check-equal? (> work 0) #t)
          (let-values (((edges inspected) (provenance-maintenance-alternatives state)))
            (check-equal? edges [])))
        (let* ((fresh (reasoning-source-snapshot 'deletion 2 '((s 1 ()))))
               (fresh-graph (candidate-positive-provenance
                             fresh spec 'program 'complete [] 64)))
          (check-equal? (positive-provenance-status fresh-graph) 'complete)
          (check-equal? (provenance-maintenance-rows state) []))))
    (test-case "compacted previews preserve their input and final-phase exhaustion publishes nothing"
      (let* ((snapshot (reasoning-source-snapshot 'compact-preview 1 '((s 1 ((1) (1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance snapshot spec 'program 'complete '((1)) 64))
             (state (candidate-open-provenance-maintenance snapshot spec 'program 'complete '((1)) graph 64)))
        (candidate-provenance-withdraw! state '((s 1)))
        (let-values (((next work) (candidate-provenance-compact state)))
          (check-equal? (> work 1) #t)
          (check-exception (candidate-provenance-compact state (- work 1)) true)
          (check-equal? (provenance-maintenance-rows state) '((1)))
          (let-values (((exact _work) (candidate-provenance-compact state work)))
            (check-equal? (provenance-maintenance-rows exact) '((1))))
          (candidate-provenance-withdraw! next '((s 2)))
          (check-equal? (provenance-maintenance-rows next) [])
          (check-equal? (provenance-maintenance-rows state) '((1)))
          (let-values (((empty _work) (candidate-provenance-compact next)))
            (let-values (((nodes edges roots) (provenance-maintenance-size empty)))
              (check-equal? (list nodes edges roots) '(0 0 0)))
            ;; Initial selector registry survives compaction; retired cuts remain
            ;; admitted idempotently by the low-level API, without resurrection.
            (candidate-provenance-withdraw! empty '((s 1) (s 2)) 1)
            (check-equal? (provenance-maintenance-rows empty) [])))))
    (test-case "failed grounded deletion preserves the published rows and source state"
      (let* ((snapshot (reasoning-source-snapshot 'deletion-rollback 1 '((s 1 ((1))))))
             (spec (recursive-provenance-spec))
             (graph (candidate-positive-provenance
                     snapshot spec 'program 'complete '((1)) 64))
             (state (candidate-open-provenance-maintenance
                     snapshot spec 'program 'complete '((1)) graph 64)))
        (check-exception (candidate-provenance-withdraw! state '((s 1)) 1) true)
        (check-equal? (provenance-maintenance-rows state) '((1)))
        (check-exception (candidate-provenance-withdraw! state '((unknown 1))) true)
        (check-equal? (provenance-maintenance-rows state) '((1)))
        (let-values (((rows work) (candidate-provenance-withdraw! state '((s 1)))))
          (check-equal? rows []))))
    (test-case "every simultaneous source withdrawal agrees with independent matrix truth"
      (for-each
       (lambda (mask)
         (let* ((edges (edges-for-mask mask))
                (initial (matrix-closure edges))
                (snapshot (reasoning-source-snapshot 'batch-corpus mask
                            (list (list 'edge 2 edges))))
                (spec (make-reasoning-candidate
                       '((path . 2)) []
                       (list (vector '(path ?x ?y) '((edge ?x ?y)) 10)
                             (vector '(path ?x ?z) '((path ?x ?y) (edge ?y ?z)) 11))
                       (vector '(path ?x ?y) 12) '(16 64 128)))
                (graph (candidate-positive-provenance
                        snapshot spec 'batch-corpus 'complete initial 10000)))
           (for-each
            (lambda (cut)
              (let* ((selected (filter (lambda (position)
                                        (odd? (quotient cut (expt 2 (- position 1)))))
                                      (iota (length edges) 1)))
                     (remaining (filter-map
                                 (lambda (edge position)
                                   (and (not (memv position selected)) edge))
                                 edges (iota (length edges) 1)))
                     (selectors (map (lambda (position) (list 'edge position))
                                     (reverse selected)))
                     (state (candidate-open-provenance-maintenance
                             snapshot spec 'batch-corpus 'complete initial graph 10000)))
                ;; Repeated selectors denote the same occurrence, not a second
                ;; deletion. Reverse order must not select a different cut.
                (let-values (((rows work)
                              (candidate-provenance-withdraw!
                               state (append selectors selectors))))
                  (check-row-set rows (matrix-closure remaining))
                  (let-values (((again repeated-work)
                                (candidate-provenance-withdraw! state selectors)))
                    (check-row-set again rows)))))
            (iota (expt 2 (length edges))))
           (displayln "PROVENANCE-BATCH-CHECKED " mask " cuts " (expt 2 (length edges)))
           (force-output)))
       (iota 64)))
    (test-case "all sixty-four graphs preserve complete alternatives and every withdrawal"
      (for-each
       (lambda (mask)
         (let* ((edges (edges-for-mask mask))
                (expected (matrix-closure edges))
                (native (execution-paths edges))
                (snapshot (reasoning-source-snapshot 'graph-corpus mask
                            (list (list 'edge 2 edges))))
                (spec (make-reasoning-candidate
                       '((path . 2)) []
                       (list (vector '(path ?x ?y) '((edge ?x ?y)) 10)
                             (vector '(path ?x ?z) '((path ?x ?y) (edge ?y ?z)) 11))
                       (vector '(path ?x ?y) 12) '(16 64 128)))
                (graph (candidate-positive-provenance
                        snapshot spec 'corpus 'complete native 10000))
                (reference (reference-provenance
                            snapshot spec 'corpus 'complete native 10000))
                (state (candidate-open-provenance-maintenance
                        snapshot spec 'corpus 'complete native graph 10000))
                (recursive-alternatives
                 (apply + (map (lambda (path)
                                 (length (filter (lambda (edge)
                                                   (= (cadr path) (car edge))) edges)))
                               expected))))
           (check-row-set native expected)
           (check-equal? (positive-provenance-alternatives graph)
                         (reference-alternatives reference))
           (check-equal? (positive-provenance-witness graph) (reference-witness reference))
           (check-equal? (positive-provenance-status graph) 'complete)
           (check-equal? (length (positive-provenance-alternatives graph))
                         (+ (* 2 (length edges)) recursive-alternatives))
           (displayln "PROVENANCE-CHECKED " mask " complete") (force-output)
           (let loop ((remaining edges) (position 1))
             (when (pair? remaining)
               (let-values (((rows work)
                             (candidate-provenance-withdraw!
                              state (list (list 'edge position)))))
                 (check-row-set rows (matrix-closure (cdr remaining)))
                 (check-row-set rows (execution-paths (cdr remaining)))
                 (check-equal? (> work 0) #t)
                 (displayln "PROVENANCE-CHECKED " mask " withdrawal " position)
                 (force-output))
               (loop (cdr remaining) (+ position 1))))))
       (iota 64)))))
