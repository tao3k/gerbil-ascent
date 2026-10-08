;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
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
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run))

(export ascent-rule-program-test)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))
(def (r head . body) (gerbil-ascent-rule (list head) body))

(def (evaluate edges (derived-limit 32))
  (ascent-rule-fixture-evaluate edges derived-limit))

(def (rows result name)
  ((.ref result 'rows-of) name))

(def ascent-rule-program-test
  (test-suite "ASCENT positive relations with arbitrary columns"
    (test-case "declaration compilation never invokes storage or rule callbacks"
      (let* ((states 0) (extensions 0) (guards 0)
             (storage
              (.o (:: @ gerbil-ascent-set-storage-provider)
                  (.make-state (lambda () (set! states (+ states 1)) #f))
                  (.extend-rows
                   (lambda args
                     (set! extensions (+ extensions 1))
                     (apply (.ref gerbil-ascent-set-storage-provider '.extend-rows)
                            args)))))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'source 1 '((7)))
                     (gerbil-ascent-relation 'out 1 []
                       gerbil-ascent-hash-index-provider storage))
               (list (r (a 'out (v 'x)) (a 'source (v 'x))
                        (gerbil-ascent-guard '(x)
                          (lambda (_x) (set! guards (+ guards 1)) #t))))
               4 4 8))
             (relations (.ref program 'relations))
             (schema (gerbil-ascent-program-schema program relations)))
        (gerbil-ascent-prepare-program relations (.ref program 'rules) schema #f)
        (check-equal? (list states extensions guards) '(0 0 0))
        (check-equal? (rows (gerbil-ascent-evaluate-program program) 'out) '((7)))
        (check-equal? states 1)
        (check-equal? (> extensions 0) #t)
        (check-equal? (> guards 0) #t)))
    (test-case "heads split across strata retain duplicates and source rule order"
      (let* ((x (v 'x))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'source 1 '((7)))
                     (gerbil-ascent-relation 'blocked 1 [])
                     (gerbil-ascent-relation 'early 1 [])
                     (gerbil-ascent-relation 'late 1 []))
               (list (gerbil-ascent-rule
                      (list (a 'late x) (a 'early x) (a 'late x))
                      (list (a 'source x)))
                     (r (a 'late x) (a 'source x)
                        (gerbil-ascent-negation 'blocked (list x))))
               4 8 12))
             (relations (.ref program 'relations))
             (analysis
              (gerbil-ascent-prepare-program
               relations (.ref program 'rules)
               (gerbil-ascent-program-schema program relations) #f))
             (active (vector-ref analysis 4)))
        (check-equal? (vector-ref analysis 3) '#(0 0 0 1))
        (check-equal? (vector-ref analysis 6) '#((3 3 2 3) (3) () ()))
        (check-equal?
         (vector-map
          (lambda (rules)
            (map (lambda (rule)
                   (list (vector-ref rule 3)
                         (map (cut vector-ref <> 0) (vector-ref rule 0))
                         (vector-ref rule 2))) rules))
          active)
         '#(((0 (2) (0))) ((0 (3 3) ()) (1 (3) ()))))
        (let (result (gerbil-ascent-evaluate-program program))
          (check-equal? (rows result 'early) '((7)))
          (check-equal? (rows result 'late) '((7))))))
    (test-case "mixed ternary inputs derive four-column, unary and recursive rows"
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
        (check-equal? (rows result 'dependent) '((2 0) (3 1) (3 0)))
        (check-equal? (length (rows result 'successor)) 3)
        (check-equal? (not (not (member '(3 4)
                                        (rows result 'successor)))) #t)
        (check-equal? (rows result 'blocked) '((3 3)))
        (check-equal? (length (rows result 'allowed)) 2)
        (check-equal? (rows result 'denied) '((3 3)))
        (check-equal? (length (rows result 'safe-reach)) 3)
        (check-equal? (length reach) 4)
        (check-equal? (length (rows result 'node)) 3)))
    (test-case "source withdrawal recomputes without changing earlier result"
      (let* ((first (evaluate '((1 2 "a") (2 3 "b") (3 3 "c"))))
             (withdrawn (evaluate '((1 2 "a") (3 3 "c")))))
        (check-equal? (length (rows first 'reach)) 4)
        (check-equal? (length (rows withdrawn 'reach)) 2)
        (check-equal? (length (rows first 'reach)) 4)))
    (test-case "positive session retains rows across source additions"
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
    (test-case "ten thousand positive appends retain order and recover state"
      (let* ((size 10000)
             (expected (map list (iota size)))
             (program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'item 1 [])) []
               (+ size 2) size size))
             (session (gerbil-ascent-open-session program))
             (first (gerbil-ascent-session-run session)))
        (for-each
         (lambda (key)
           (gerbil-ascent-session-append-source! session 'item (list key)))
         (iota size))
        (let (second (gerbil-ascent-session-run session))
          (check-equal? (rows second 'item) expected)
          (gerbil-ascent-session-append-source! session 'item '(0))
          (check-exception
           (gerbil-ascent-session-append-source! session 'item '(0 1))
           true)
          (check-equal? (rows (gerbil-ascent-session-run session) 'item)
                        expected)
          (gerbil-ascent-session-replace-source! session 'item '((42)))
          (check-equal? (rows (gerbil-ascent-session-run session) 'item)
                        '((42)))
          (check-equal? (rows second 'item) expected)
          (check-equal? (rows first 'item) []))))
    (test-case "staged Set rows share one global output budget"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'left 1 [])
                     (gerbil-ascent-relation 'right 1 []))
               [] 4 4 1))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (gerbil-ascent-session-append-source! session 'left '(1))
        (check-exception
         (gerbil-ascent-session-append-source! session 'right '(2))
         true)
        (let (first (gerbil-ascent-session-run session))
          (check-equal? (rows first 'left) '((1)))
          (check-equal? (rows first 'right) [])
          (gerbil-ascent-session-append-source! session 'left '(1))
          (check-equal? (eq? first (gerbil-ascent-session-run session))
                        #t)
          (check-exception
           (gerbil-ascent-session-append-source! session 'right '(1))
           true)
          (check-equal? (eq? first (gerbil-ascent-session-run session))
                        #t))))
    (test-case "batched Set duplicates retain first source order"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'item 1 []))
               [] 6 6 3))
             (session (gerbil-ascent-open-session program)))
        (gerbil-ascent-session-run session)
        (for-each
         (lambda (row)
           (gerbil-ascent-session-append-source! session 'item row))
         '((1) (2) (1) (3)))
        (let (first (gerbil-ascent-session-run session))
          (check-equal? (rows first 'item) '((1) (2) (3)))
          (gerbil-ascent-session-append-source! session 'item '(2))
          (check-equal? (eq? first (gerbil-ascent-session-run session))
                        #t))))
    (test-case "session recomputes negation after source updates"
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
        (let (first (gerbil-ascent-session-run session))
          (check-equal? (rows first 'allowed) '((1)))
          (gerbil-ascent-session-append-source! session 'blocked '(1))
          (let (second (gerbil-ascent-session-run session))
            (check-equal? (rows second 'allowed) [])
            (check-equal? (rows first 'allowed) '((1)))
            (check-equal? (eq? second (gerbil-ascent-session-run session))
                          #t)
            (check-exception
             (gerbil-ascent-session-replace-source!
              session 'blocked '((1 2)))
             true)
            (check-equal? (eq? second (gerbil-ascent-session-run session))
                          #t)
            (gerbil-ascent-session-replace-source! session 'blocked [])
            (gerbil-ascent-session-append-source! session 'candidate '(2))
            (check-equal?
             (length (rows (gerbil-ascent-session-run session) 'allowed))
             2)
            (check-equal? (rows first 'allowed) '((1)))
            (check-equal? (rows second 'allowed) [])))))
    (test-case "nonpositive recomputation rejects over-budget source atomically"
      (let* ((program
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'candidate 1 '((1)))
                     (gerbil-ascent-relation 'blocked 1 [])
                     (gerbil-ascent-relation 'allowed 1 []))
               (list (r (a 'allowed (v 'x))
                        (a 'candidate (v 'x))
                        (gerbil-ascent-negation 'blocked (list (v 'x)))))
               4 4 3))
             (session (gerbil-ascent-open-session program))
             (first (gerbil-ascent-session-run session)))
        (check-exception
         (gerbil-ascent-session-append-source! session 'candidate '(2))
         true)
        (check-exception
         (gerbil-ascent-session-replace-source!
          session 'candidate '((1) (2)))
         true)
        (check-equal? (eq? first (gerbil-ascent-session-run session)) #t)
        (gerbil-ascent-session-append-source! session 'blocked '(1))
        (check-equal?
         ((.ref (gerbil-ascent-session-run session) 'rows-of) 'allowed)
         [])
        (check-equal? (rows first 'allowed) '((1)))))
    (test-case "empty rule set preserves sources and returns"
      (let (result
            (gerbil-ascent-evaluate-program
             (gerbil-ascent-program
              (list (gerbil-ascent-relation 'r 1 '((1)))) [] 2 2 2)))
        (check-equal? (rows result 'r) '((1)))))
    (test-case "POO rule refinement receives its own immutable analysis"
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
    (test-case "zero-column fact gates typed boolean and string rows"
      (check-equal?
       (rows (ascent-typed-program-evaluate
              #f '((#t "alpha"))) 'selected)
       [])
      (check-equal?
       (rows (ascent-typed-program-evaluate
              #t '((#t "alpha") (#f "beta") (#f "beta")))
             'selected)
       '((#t "alpha") (#f "beta"))))
    (test-case "arity, unsafe heads, and derived budgets reject"
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
                  (gerbil-ascent-generator 'x []
                                           (lambda () 'not-iterable))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-generator '(x x) []
                                (lambda () '#(#(1 2)))) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (gerbil-ascent-generator '(x y) []
                                           (lambda () '#(#(1))))))
         2 2 3)) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (gerbil-ascent-program
         (list (gerbil-ascent-relation 'source 1 '((1)))
               (gerbil-ascent-relation 'out 1 []))
         (list (r (a 'out (v 'x))
                  (a 'source (v 'x))
                  (gerbil-ascent-generator '(x y) []
                                           (lambda () '#(#(1 2))))))
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
