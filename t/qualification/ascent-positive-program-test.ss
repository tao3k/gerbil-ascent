;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow-foundation/module-system/observability/debug
                 poo-flow-debug-memory-policy)
        (only-in :poo-flow-foundation/module-system/observability/testing-case
                 poo-flow-default-testing-case-profile
                 poo-flow-test-case/with)
        (only-in :gerbil-ascent/t/qualification/ascent-positive-program-fixture
                 ascent-positive-fixture-evaluate)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-literal gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-positive-program
                 gerbil-ascent-evaluate-positive-program))

(export ascent-positive-program-test)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule head body))

;;; ASCENT contributes only its Case budget to Foundation's native profile.
(def +positive-case-profile+
  (.o (:: @ poo-flow-default-testing-case-profile)
      (identity 'ascent/positive-case)
      (memory-policy
       (poo-flow-debug-memory-policy
        'ascent/positive-case heap-limit-bytes: 1073741824
        live-growth-limit-bytes: 16777216
        sample-interval-milliseconds: 10
        collect-before-sample?: #t))
      (max-duration-milliseconds 2000)))

(def (evaluate edges (derived-limit 32))
  (ascent-positive-fixture-evaluate edges derived-limit))

(def (rows result name)
  ((.ref result 'rows-of) name))

(def ascent-positive-program-test
  (test-suite "ASCENT positive relations with arbitrary columns"
    (poo-flow-test-case/with +positive-case-profile+
      "mixed ternary inputs derive four-column, unary and recursive rows"
      (let* ((source '((1 2 "a") (2 3 "b") (3 3 "c") (1 2 "a")))
             (result (evaluate source))
             (labelled (rows result 'labelled))
             (reach (rows result 'reach)))
        (check-equal? (length (rows result 'edge)) 3)
        (check-equal? (length labelled) 3)
        (check-equal? (not (not (member '(1 3 "a" "b") labelled))) #t)
        (check-equal? (not (not (member '(2 3 "b" "c") labelled))) #t)
        (check-equal? (not (not (member '(3 3 "c" "c") labelled))) #t)
        (check-equal? (rows result 'cycle) '((3)))
        (check-equal? (rows result 'hot) '((1)))
        (check-equal? (length reach) 4)
        (check-equal? (length (rows result 'node)) 3)))
    (poo-flow-test-case/with +positive-case-profile+
      "source withdrawal recomputes without changing earlier result"
      (let* ((first (evaluate '((1 2 "a") (2 3 "b") (3 3 "c"))))
             (withdrawn (evaluate '((1 2 "a") (3 3 "c")))))
        (check-equal? (length (rows first 'reach)) 4)
        (check-equal? (length (rows withdrawn 'reach)) 2)
        (check-equal? (length (rows first 'reach)) 4)))
    (poo-flow-test-case/with +positive-case-profile+
      "empty rule set preserves sources and returns"
      (let (result
            (gerbil-ascent-evaluate-positive-program
             (gerbil-ascent-positive-program
              (list (gerbil-ascent-relation 'r 1 '((1)))) [] 2 2 2)))
        (check-equal? (rows result 'r) '((1)))))
    (poo-flow-test-case/with +positive-case-profile+
      "arity, unsafe heads, and derived budgets reject"
      (check-exception
       (gerbil-ascent-relation 'broken 2 '((1))) true)
      (check-exception (gerbil-ascent-atom 'out '(raw-term)) true)
      (check-exception
       (gerbil-ascent-positive-program [] [] 0 2 2) true)
      (check-exception (evaluate '((1 2 "a") (2 3 "b")) 1) true)
      (check-exception
       (gerbil-ascent-evaluate-positive-program
        (gerbil-ascent-positive-program
         (list (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'free)))) 2 2 2)) true)
      (check-equal? (.ref (gerbil-ascent-literal "x") 'value) "x"))))
