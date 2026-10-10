;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/rule-semantics
 (prefix-in :gerbil-ascent/t/performance/rule-reads/reference old-))
(export ascent-rule-reads-test)
(def (outcome solve plans kinds)
 (with-catch (lambda (e) (error-message e))
   (lambda () (solve plans (vector-length kinds) kinds))))
(def ascent-rule-reads-test
 (test-suite "Rule-local dependency read projection"
  (test-case "ordered duplicate successors and strict lattice strata agree"
   (let* ((plans (list
           (vector (list (vector 2 []) (vector 3 []) (vector 2 []))
             (list (vector 'atom (vector 0 [])) (vector 'guard #f)
                   (vector 'negation (vector 1 [])) (vector 'binding #f)
                   (vector 'aggregate (vector 0 []))))
           (vector (list (vector 1 [])) (list (vector 'atom (vector 0 []))))))
          (expected '#((1 2 3 2 2 3 2) (2 3 2) () ())))
    (check-equal? (gerbil-ascent-rule-successors plans 4) expected)
    (check-equal? (gerbil-ascent-rule-successors plans 4)
                  (old-gerbil-ascent-rule-successors plans 4))
    (check-equal? (gerbil-ascent-rule-strata plans 4 '#(relation relation relation relation)) '#(0 0 1 1))
    (check-equal? (gerbil-ascent-rule-strata plans 4 '#(lattice relation relation relation)) '#(0 1 2 2))))
  (test-case "separate invocations reread caller metadata without retaining descriptors"
   (let* ((atom (vector 0 [])) (clause (vector 'negation atom))
          (head (vector 2 [])) (heads (list head)) (body (list clause))
          (plans (list (vector heads body))) (kinds '#(relation relation relation)))
    (check-equal? (gerbil-ascent-rule-successors plans 3) '#((2) () ()))
    (vector-set! atom 0 1)
    (check-equal? (gerbil-ascent-rule-successors plans 3) '#(() (2) ()))
    (check-equal? (outcome gerbil-ascent-rule-strata plans kinds)
                  (outcome old-gerbil-ascent-rule-strata plans kinds))
    (vector-set! atom 0 2)
    (check-equal? (outcome gerbil-ascent-rule-strata plans kinds)
                  "unstratifiable ASCENT negation cycle")
    (vector-set! clause 0 'guard)
    (check-equal? (gerbil-ascent-rule-successors plans 3) '#(() () ()))
    (check-equal? (gerbil-ascent-rule-strata plans 3 kinds) '#(0 0 0))
    (check-equal? (eq? (vector-ref (car plans) 0) heads) #t)
    (check-equal? (eq? (vector-ref (car plans) 1) body) #t)))
  (test-case "planning ignores callback payloads and preserves caller lists"
   (let* ((callback (lambda args (error "planning invoked callback")))
          (heads (list (vector 1 [])))
          (body (list (vector 'guard callback) (vector 'binding callback)
                      (vector 'generator callback) (vector 'negation (vector 0 []))))
          (plans (list (vector heads body))))
    (check-equal? (gerbil-ascent-rule-successors plans 2) '#((1) ()))
    (check-equal? (gerbil-ascent-rule-strata plans 2 '#(relation relation)) '#(0 1))
    (check-equal? (eq? (vector-ref (car plans) 1) body) #t)
    (check-equal? (length body) 4)))))
