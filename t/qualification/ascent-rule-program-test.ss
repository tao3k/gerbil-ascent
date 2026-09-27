;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .o .ref)
        (only-in :core/observability/debug
                 poo-flow-debug-memory-policy)
        (only-in :core/observability/testing-case
                 poo-flow-default-testing-case-profile
                 poo-flow-test-case/with)
        (only-in :gerbil-ascent/t/qualification/ascent-rule-program-fixture
                 ascent-rule-fixture-evaluate)
        (only-in :gerbil-ascent/t/qualification/ascent-typed-program-fixture
                 ascent-typed-program-evaluate)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-literal gerbil-ascent-atom
                 gerbil-ascent-guard gerbil-ascent-generator
                 gerbil-ascent-binding
                 gerbil-ascent-negation
                 gerbil-ascent-rule
                 gerbil-ascent-program
                 gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(export ascent-rule-program-test)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

;;; ASCENT contributes only its Case budget to Core's native profile.
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

;;; This case constructs and evaluates two separately admitted POO programs.
;;; Keep its memory policy while allowing the second contract admission.
(def +two-snapshot-case-profile+
  (.o (:: @ +positive-case-profile+)
      (identity 'ascent/two-snapshot-case)
      (max-duration-milliseconds 5000)))

(def (evaluate edges (derived-limit 32))
  (ascent-rule-fixture-evaluate edges derived-limit))

(def (rows result name)
  ((.ref result 'rows-of) name))

(def ascent-rule-program-test
  (test-suite "ASCENT positive relations with arbitrary columns"
    (poo-flow-test-case/with +positive-case-profile+
      "mixed ternary inputs derive four-column, unary and recursive rows"
      (let* ((source '((1 2 "a") (2 3 "b") (3 3 "c") (1 2 "a")))
             (result (evaluate source))
             (labelled (rows result 'labelled))
             (reach (rows result 'reach)))
        (check-equal? (length (rows result 'edge)) 4)
        (check-equal? (length labelled) 3)
        (check-equal? (not (not (member '(1 3 "a" "b") labelled))) #t)
        (check-equal? (not (not (member '(2 3 "b" "c") labelled))) #t)
        (check-equal? (not (not (member '(3 3 "c" "c") labelled))) #t)
        (check-equal? (rows result 'cycle) '((3)))
        (check-equal? (rows result 'hot) '((1)))
        (check-equal? (rows result 'selected) '((1 2)))
        (check-equal? (length (rows result 'choice)) 6)
        (check-equal? (not (not (member '(1 2) (rows result 'choice)))) #t)
        (check-equal? (member '(1 1) (rows result 'choice)) #f)
        (check-equal? (length (rows result 'generated)) 3)
        (check-equal? (rows result 'dependent) '((1 2) (2 4) (3 6)))
        (check-equal? (length (rows result 'successor)) 3)
        (check-equal? (not (not (member '(3 4)
                                        (rows result 'successor)))) #t)
        (check-equal? (rows result 'blocked) '((3 3)))
        (check-equal? (length (rows result 'allowed)) 2)
        (check-equal? (rows result 'denied) '((3 3)))
        (check-equal? (length (rows result 'safe-reach)) 3)
        (check-equal? (length reach) 4)
        (check-equal? (length (rows result 'node)) 3)))
    (poo-flow-test-case/with +two-snapshot-case-profile+
      "source withdrawal recomputes without changing earlier result"
      (let* ((first (evaluate '((1 2 "a") (2 3 "b") (3 3 "c"))))
             (withdrawn (evaluate '((1 2 "a") (3 3 "c")))))
        (check-equal? (length (rows first 'reach)) 4)
        (check-equal? (length (rows withdrawn 'reach)) 2)
        (check-equal? (length (rows first 'reach)) 4)))
    (poo-flow-test-case/with +two-snapshot-case-profile+
      "positive session retains rows across source additions"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'edge 2 '((1 2)))
                     (gerbil-ascent-relation 'reach 2 []))
               (list (r (a 'reach (v 'x) (v 'y))
                        (a 'edge (v 'x) (v 'y)))
                     (r (a 'reach (v 'x) (v 'z))
                        (a 'reach (v 'x) (v 'y))
                        (a 'edge (v 'y) (v 'z))))
               8 16 32))
             (session (gerbil-ascent-open-session program))
             (first (gerbil-ascent-session-run session)))
        (check-equal? (rows first 'reach) '((1 2)))
        (check-equal? (eq? first (gerbil-ascent-session-run session)) #t)
        (gerbil-ascent-session-append-source! session 'edge '(2 3))
        (let (second (gerbil-ascent-session-run session))
          (check-equal? (length (rows second 'reach)) 3)
          (check-equal? (not (not (member '(1 3) (rows second 'reach)))) #t)
          (gerbil-ascent-session-append-source! session 'edge '(2 3))
          (check-equal? (length (rows (gerbil-ascent-session-run session)
                                     'reach)) 3)
          (gerbil-ascent-session-append-source! session 'edge '(3 1))
          (check-equal? (length (rows (gerbil-ascent-session-run session)
                                     'reach)) 9)
          (check-equal? (length (rows second 'reach)) 3)
          (check-equal? (rows first 'reach) '((1 2))))))
    (poo-flow-test-case/with +positive-case-profile+
      "session rejects source updates through negation"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'candidate 1 '((1)))
                     (gerbil-ascent-relation 'blocked 1 [])
                     (gerbil-ascent-relation 'allowed 1 []))
               (list (r (a 'allowed (v 'x))
                        (a 'candidate (v 'x))
                        (gerbil-ascent-negation 'blocked (list (v 'x)))))
               4 4 8))
             (session (gerbil-ascent-open-session program)))
        (check-equal? (rows (gerbil-ascent-session-run session)
                            'allowed) '((1)))
        (check-exception
         (gerbil-ascent-session-append-source!
          session 'blocked '(1)) true)
        (check-equal? (rows (gerbil-ascent-session-run session)
                            'allowed) '((1)))))
    (poo-flow-test-case/with +positive-case-profile+
      "empty rule set preserves sources and returns"
      (let (result
            (gerbil-ascent-evaluate-program
             (gerbil-ascent-program
              (list (gerbil-ascent-relation 'r 1 '((1)))) [] 2 2 2)))
        (check-equal? (rows result 'r) '((1)))))
    (poo-flow-test-case/with +two-snapshot-case-profile+
      "POO rule refinement receives its own immutable analysis"
      (let* ((base
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'edge 1 '((1)))
                     (gerbil-ascent-relation 'reach 1 []))
               (list (r (a 'reach (v 'x)) (a 'edge (v 'x))))
               4 4 8))
             (first (gerbil-ascent-evaluate-program base))
             (refined
              (.o (:: @ base)
                  rules: (append (.ref base 'rules)
                                 (list (r (a 'reach (gerbil-ascent-literal 2)))))))
             (second (gerbil-ascent-evaluate-program refined)))
        (check-equal? (rows first 'reach) '((1)))
        (check-equal? (length (rows second 'reach)) 2)
        (check-equal? (not (not (member '(2) (rows second 'reach)))) #t)
        (check-equal? (rows (gerbil-ascent-evaluate-program base) 'reach)
                      '((1)))))
    (poo-flow-test-case/with +positive-case-profile+
      "zero-column fact gates typed boolean and string rows"
      (check-equal?
       (rows (ascent-typed-program-evaluate
              #f '((#t "alpha"))) 'selected)
       [])
      (check-equal?
       (rows (ascent-typed-program-evaluate
              #t '((#t "alpha") (#f "beta") (#f "beta")))
             'selected)
       '((#t "alpha") (#f "beta"))))
    (poo-flow-test-case/with +positive-case-profile+
      "arity, unsafe heads, and derived budgets reject"
      (check-exception
       (gerbil-ascent-relation 'broken 2 '((1))) true)
      (check-exception (gerbil-ascent-atom 'out '(raw-term)) true)
      (check-exception
       (gerbil-ascent-program [] [] 0 2 2) true)
      (check-exception (evaluate '((1 2 "a") (2 3 "b")) 1) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'free)))) 2 2 2)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'source 1 '((1)))
               (gerbil-ascent-relation 'out 1 [])
               (gerbil-ascent-relation 'bad 1 []))
         (list (gerbil-ascent-rule
                (list (a 'out (v 'x)) (a 'bad (v 'free)))
                (list (a 'source (v 'x)))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (gerbil-ascent-guard '(x) (lambda (x) #t))
                  (gerbil-ascent-generator 'x [] (lambda () '(1)))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (gerbil-ascent-generator 'x '(missing)
                                           (lambda (_) '(1)))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'source 1 '((1)))
               (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (a 'source (v 'x))
                  (gerbil-ascent-generator 'x [] (lambda () '(2)))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'source 1 '((1)))
               (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (a 'source (v 'x))
                  (gerbil-ascent-guard '(x) (lambda (_) 'yes))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (gerbil-ascent-generator 'x [] (lambda () '#(1)))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'node 1 '((1)))
               (gerbil-ascent-relation 'left 1 [])
               (gerbil-ascent-relation 'right 1 []))
         (list (r (a 'left (v 'x))
                  (a 'node (v 'x))
                  (gerbil-ascent-negation 'right (list (v 'x))))
               (r (a 'right (v 'x))
                  (a 'node (v 'x))
                  (gerbil-ascent-negation 'left (list (v 'x)))))
         3 3 6)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'left 1 [])
               (gerbil-ascent-relation 'right 1 []))
         (list (r (a 'left (v 'x))
                  (gerbil-ascent-negation 'right (list (v 'x)))))
         3 3 6)) true)
      (check-equal? (.ref (gerbil-ascent-literal "x") 'value) "x"))))
