;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/positive-plan
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
(def ascent-rule-cost-kernel-test
  (test-suite "Native positive-plan cost charge points"
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
