;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :gerbil-ascent/candidate/provenance
        (prefix-in :gerbil-ascent/t/performance/proof-verification/reference old-)
        :gerbil-ascent/t/performance/proof-verification/fixture
        (only-in :gerbil-ascent/candidate/checked-program reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate))
(export ascent-proof-verification-test)

(def (check-replay source spec expected verdict)
  (for-each
   (lambda (old?)
     (let (proof ((if old? old-candidate-positive-proof candidate-positive-proof)
                   source spec 'test 'complete expected 10000))
       (check-equal? ((if old? old-positive-proof-status positive-proof-status) proof) 'complete)
       (check-equal? ((if old? old-candidate-verify-positive-proof candidate-verify-positive-proof)
                      source spec 'test 'complete expected proof 4096) verdict))) '(#t #f)))

(def ascent-proof-verification-test
  (test-suite "complete independent positive proof verification"
    (test-case "full wide mixed cold source and forged consumers match fixed truth"
      (for-each (lambda (scenario)
        (for-each (lambda (old?)
          (let (state (verification-prepare old? scenario))
            (check-equal? (verification-consume state scenario old?)
                          (not (eq? scenario 'forged))))) '(#t #f)))
        '(wide mixed cold small source forged)))
    (test-case "repeat verification cannot retain a verdict after proof mutation"
      (for-each (lambda (old?)
        (let* ((state (verification-prepare old? 'small)) (proof (vector-ref state 4))
               (nodes ((if old? old-positive-proof-nodes positive-proof-nodes) proof)))
          (check-equal? (verification-consume state 'small old?) #t)
          (set-car! ((if old? old-proof-node-row proof-node-row) (car (last-pair nodes))) -1)
          (check-equal? (verification-consume state 'small old?) #f))) '(#t #f)))
    (test-case "ordered source occurrence positions retain duplicate rows"
      (let* ((source (reasoning-source-snapshot 'duplicates 0 '((edge 2 ((#f 2) (#f 2) (#f 4))))))
             (spec (make-reasoning-candidate '((out . 2)) []
                     (list (vector '(out ?flag ?value)
                       '((edge ?flag ?x) (where (even? ?x))
                         (compute ?value (+ ?x ?x))) 'derive))
                     (vector '(out ?flag ?value) 0) '(16 32 64))))
        (check-replay source spec '((#f 4) (#f 8)) #t)))
    (test-case "wildcards repeated bindings and false identity remain distinct"
      (let ((source (reasoning-source-snapshot 'bindings 0 '((edge 2 ((#f #f) (#f 2) (2 2)))))))
        (check-replay source
          (make-reasoning-candidate '((out . 1)) []
            (list (vector '(out ?v) '((edge ?x ?x) (compute ?v (identity ?x))) 'same))
            (vector '(out ?v) 0) '(16 32 64)) '((#f) (2)) #t)
        (check-replay source
          (make-reasoning-candidate '((out . 1)) []
            (list (vector '(out ?v) '((edge ?_ ?x) (where (even? ?x))
                                      (compute ?v (+ ?x ?x))) 'wild))
            (vector '(out ?v) 0) '(16 32 64)) '((4)) #t)))
    (test-case "duplicate rule labels keep the first rule as replay owner"
      (let* ((source (reasoning-source-snapshot 'labels 0 '((edge 1 ((0) (2))))))
             (spec (make-reasoning-candidate '((out . 1)) []
                     (list (vector '(out ?x) '((edge ?x)) 'same)
                           (vector '(out ?v) '((edge ?x) (edge ?two)
                                               (compute ?v (+ ?x ?two))) 'same))
                     (vector '(out ?v) 0) '(16 32 64))))
        (check-replay source spec '((0) (2) (4)) #f)))
    (test-case "successful prefix facts cannot bypass a later conflicting atom"
      (for-each (lambda (value)
        (let* ((source (reasoning-source-snapshot 'prefix 0
                         (list (list 'left 1 '((0))) (list 'right 1 (list '(0) (list value))))))
               (spec (make-reasoning-candidate '((out . 1)) []
                       (list (vector '(out ?x)
                         '((left ?x) (where (even? ?x)) (right ?x)
                           (where (even? ?x))) 'prefix))
                       (vector '(out ?x) 0) '(16 32 64))))
          (for-each (lambda (old?)
            (let* ((proof ((if old? old-candidate-positive-proof candidate-positive-proof)
                           source spec 'prefix 'complete '((0)) 10000))
                   (nodes ((if old? old-positive-proof-nodes positive-proof-nodes) proof))
                   (node-row (if old? old-proof-node-row proof-node-row))
                   (node-relation (if old? old-proof-node-relation proof-node-relation))
                   (right (car (filter (lambda (node)
                                        (and (eq? (node-relation node) 'right)
                                             (equal? (node-row node) (list value)))) nodes)))
                   (inputs ((if old? old-proof-node-inputs proof-node-inputs) (car (last-pair nodes)))))
              (check-equal? ((if old? old-positive-proof-status positive-proof-status) proof) 'complete)
              (set-car! (cdr inputs) ((if old? old-proof-node-id proof-node-id) right))
              (check-equal? ((if old? old-candidate-verify-positive-proof candidate-verify-positive-proof)
                             source spec 'prefix 'complete '((0)) proof 4096)
                            (equal? value 0)))) '(#t #f))))
        '(0 1 #f #t other)))
    (test-case "computed bindings remain checked by following atom occurrences"
      (let* ((source (reasoning-source-snapshot 'computed 0
                       '((edge 2 ((#f #f) (#f 1) (2 2))))))
             (spec (make-reasoning-candidate '((out . 1)) []
                     (list (vector '(out ?v)
                       '((edge ?x ?_) (compute ?v (identity ?x)) (edge ?x ?v)) 'computed))
                     (vector '(out ?v) 0) '(16 32 64))))
        (check-replay source spec '((#f) (2)) #t)))
    (test-case "literal query roots filter the verified complete answer"
      (let* ((source (reasoning-source-snapshot 'literal 0 '((edge 2 ((#f 0) (#t 2))))))
             (spec (make-reasoning-candidate '((out . 2)) []
                     (list (vector '(out ?flag ?x) '((edge ?flag ?x)) 'literal))
                     (vector '(out #f ?_) 0) '(16 32 64))))
        (check-replay source spec '((#f 0)) #t)))))
