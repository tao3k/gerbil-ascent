;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .ref)
 :gerbil-ascent/program/interface :gerbil-ascent/program/evaluate
 :gerbil-ascent/core/positive-plan :gerbil-ascent/program/index
 :gerbil-ascent/table/provider :gerbil-ascent/program/actor-round
 (only-in :gerbil-ascent/program/objects gerbil-ascent-construct-inert-program)
 (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-schema)
 (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
 (only-in :gerbil-ascent/program/reuse gerbil-ascent-activate-rules)
 :gerbil-ascent/t/qualification/fixtures/semi-naive/oracle)
(export ascent-semi-naive-test)
;; BEGIN GENERATED DSL-WORKLOAD
(def (declaration edges rules)
 (def (atom form) (gerbil-ascent-atom (car form) (map gerbil-ascent-variable (cdr form))))
 (gerbil-ascent-program
  (list (gerbil-ascent-relation 'edge 2 edges) (gerbil-ascent-relation 'p 2 []) (gerbil-ascent-relation 'q 2 []))
  (map (lambda (rule) (gerbil-ascent-rule (list (atom (car rule))) (map atom (cdr rule)))) rules)
  10000 10000 10000))
(def (owned-declaration edges rules)
 ;; This fixture supplies only closed integer rows and fixed rule data.
 ;; Preserve the exact public schema, including callback-free Actor fields.
 (gerbil-ascent-construct-inert-program (lambda () (declaration edges rules)) #f))
(def (verify mask rules workers)
 (let* ((edges (graph-input mask)) (program (if (= workers 1) (declaration edges rules) (owned-declaration edges rules)))
        (actual (gerbil-ascent-evaluate-program program workers: workers)))
  (let-values (((expected _) (naive-positive edges rules)))
   (check-equal? (.ref actual 'finished) #t)
   (for-each (lambda (name)
     (check-equal? (canonical-rows ((.ref actual 'rows-of) name))
                   (canonical-rows (cdr (assq name expected))))) '(edge p q)))))
(def ascent-semi-naive-test
 (test-suite "Independent least fixed point and disjoint delta witnesses"
  (test-case "all three-node graphs agree with independent naive consequences"
   (for-each (lambda (mask) (verify mask naive-rules 1)
     (verify mask (reverse naive-rules) 1)) (iota 512)))
  (test-case "Actor reschedules empty consumers and nonlinear mutual recursion"
   (let* ((sample (owned-declaration (graph-input 511) naive-rules))
          (relations (.ref sample 'relations))
          (schema (gerbil-ascent-program-schema sample relations))
          (analysis (gerbil-ascent-prepare-program relations (.ref sample 'rules) schema #f)))
     (check-equal? (gerbil-ascent-actor-round-eligible?
                    (apply append (vector->list (gerbil-ascent-activate-rules analysis))) (vector-ref schema 9) (vector-ref schema 5)
                    (vector-ref schema 7) (vector-ref schema 3)) #t))
   (for-each (lambda (workers)
    (for-each (lambda (mask)
     (verify mask naive-rules workers)
     (verify mask (reverse naive-rules) workers)) (iota 512))) '(2 4)))
;; END GENERATED DSL-WORKLOAD
  (test-case "first fresh occurrence partitions actual compiled join witnesses"
   (let* ((all (vector '((0 1) (1 2) (2 0)))) (delta (vector '((1 2) (2 0))))
          (sizes (vector 3)) (dsizes (vector 2)) (versions (vector 0)) (dversions (vector 0))
          (provider gerbil-ascent-hash-index-provider)
          (indexes (gerbil-ascent-make-row-indexes all delta sizes dsizes versions dversions (vector provider)))
          (first (vector 0 '((variable . x) (variable . y)) [] [] []))
          (second (vector 0 '((variable . y) (variable . z)) [] [] []))
          (head (vector 0 '((variable . x) (variable . z))))
          (plan (gerbil-ascent-compile-positive-plan (list head) (list (vector 'atom first) (vector 'atom second))))
          (overlap 0) (disjoint 0) (checks 0))
     (for-each (lambda (pivot)
      (gerbil-ascent-run-positive-plan! plan (make-vector 3 #f) pivot (row-indexes-rows indexes)
       (lambda (_ row) (set! overlap (+ overlap 1))))
      (gerbil-ascent-run-positive-plan! plan (make-vector 3 #f) pivot (row-indexes-rows indexes)
       (lambda (_ row) (set! disjoint (+ disjoint 1)))
       (lambda () (set! checks (+ checks 1))) #f (row-indexes-old-rows indexes))) '(0 1))
     (check-equal? overlap 4)
     (check-equal? disjoint 3)
     (let (actor-count 0)
       (gerbil-ascent-run-actor-round! (vector 'delta-witnesses) '(0 1) 2
        (lambda (pivot emit! checkpoint!)
          (let (private (gerbil-ascent-make-row-indexes all delta sizes dsizes versions dversions (vector provider)))
            (gerbil-ascent-run-positive-plan! plan (make-vector 3 #f) pivot
             (row-indexes-rows private) emit! checkpoint! #f (row-indexes-old-rows private))))
        (lambda (_ row) (set! actor-count (+ actor-count 1))))
       (check-equal? actor-count disjoint))
     (check-equal? (> checks 0) #t)
     ;; Same-size replacement must invalidate membership by version.
     (vector-set! delta 0 '((0 1) (1 2)))
     (vector-set! dversions 0 1)
     (check-equal? ((row-indexes-old-rows indexes) first (make-vector 3 #f) [] #f) '((2 0)))
     ;; With only (2 0) fresh, (0 1) join (1 2) is entirely old.
     ;; Observe the actual traversal before head dedup can hide that work.
     (vector-set! delta 0 '((2 0)))
     (vector-set! dsizes 0 1)
     (vector-set! dversions 0 2)
     (let ((full 0) (fresh []))
       (gerbil-ascent-run-positive-plan! plan (make-vector 3 #f) -1 (row-indexes-rows indexes)
        (lambda (_ row) (set! full (+ full 1))))
       (for-each (lambda (pivot)
         (gerbil-ascent-run-positive-plan! plan (make-vector 3 #f) pivot (row-indexes-rows indexes)
          (lambda (_ row) (set! fresh (cons row fresh))) #f #f (row-indexes-old-rows indexes))) '(0 1))
       (check-equal? full 3)
       (check-equal? (length fresh) 2)
       (check-equal? (member '(0 2) fresh) #f))
     (displayln "DELTA-COUNTS scheme overlap=" overlap " disjoint=" disjoint)))
  (test-case "old-lane membership construction obeys interruption"
   (let* ((all (vector '((0 1) (1 2)))) (delta (vector '((0 1))))
          (indexes (gerbil-ascent-make-row-indexes all delta '#(2) '#(1) '#(0) '#(0)
                     (vector gerbil-ascent-hash-index-provider)))
          (atom (vector 0 '((variable . x) (variable . y)) [] [] [])))
    (check-exception
     ((row-indexes-old-rows indexes) atom [] [] (lambda () (error "canceled")))
     (lambda (_) #t))))))
