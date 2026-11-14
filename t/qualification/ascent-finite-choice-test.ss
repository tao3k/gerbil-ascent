;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :gerbil-ascent/program/api relational-choice-program relational-choice-solve
                 RelationalChoiceLimit? relational-program-query)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control)
        (only-in "../../dev/finite-choice/oracle.ss" finite-choice-solutions))

(export ascent-finite-choice-test)

(def (choice-chain edges)
  (relational-choice-program
    (relation edge (left right) edges)
    (relation path (left right))
    (choice color (node value))
    (rule (path ?x ?y) (edge ?x ?y))
    (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
    (rule (closed (color 0) (0 1)))
    (rule (open (color ?y) ?v) (color 0 ?v) (path 0 ?y))
    (rule (closed (color ?y) ()) (color 0 0) (edge 0 ?y) (color ?y 1))
    (limits 128 128 128)))

(def (ground-reference edges)
  ;; Independent reachability oracle for the test graph. It operates on
  ;; ordinary edge rows and builds a separate ground program for the reference.
  (let visit ((frontier '(0)) (reached []))
    (if (null? frontier)
      (let (reachable (filter (lambda (node) (not (= node 0))) reached))
        (finite-choice-solutions
         (cons '(closed 0 (0 1) ())
           (append
            (foldl (lambda (node rules)
                     (cons (list 'open node 0 '((0 . 0)))
                           (cons (list 'open node 1 '((0 . 1))) rules))) [] reachable)
            (filter-map (lambda (edge)
                          (and (= (car edge) 0)
                               (list 'closed (cadr edge) [] (list '(0 . 0) (cons (cadr edge) 1)))))
                        edges)))
         void))
      (let (node (car frontier))
        (if (memv node reached) (visit (cdr frontier) reached)
          (visit (foldl (lambda (edge work)
                         (if (= (car edge) node) (cons (cadr edge) work) work))
                        (cdr frontier) edges)
                 (cons node reached)))))))

(def (model-colors models)
  (map (lambda (model)
         (list-sort (lambda (a b) (< (car a) (car b)))
           (map (lambda (row) (cons (car row) (cadr row)))
                (relational-program-query model 'color))))
       models))

(def (check-chain edges)
  (let* ((expected (ground-reference edges))
         (models (relational-choice-solve (choice-chain edges) state-budget: 64))
         (actual (model-colors models)))
    (check-equal? (length actual) (length expected))
    (check-equal? (andmap (lambda (row) (and (member row actual) #t)) expected) #t)
    models))

(def ascent-finite-choice-test
  (test-suite "Finite-choice grounding through checked ASCENT"
    (test-case "recursive joins ground newly enabled heads with branch-local sources"
      (let* ((models (check-chain '((0 1) (1 2))))
             (before (model-colors models))
             (rows (relational-program-query (car models) 'color)))
        (check-equal? (length models) 2)
        (set-car! (car rows) -1)
        (check-equal? (model-colors models) before)
        (check-chain '((0 2)))
        (check-equal? (model-colors models) before)))
    (test-case "every subset of a small diamond agrees with independent grounding"
      (let (edges '((0 1) (0 2) (1 3) (2 3)))
        (for-each (lambda (mask)
                    (check-chain
                     (filter-map (lambda (edge position) (and (bit-set? position mask) edge))
                                 edges (iota 4))))
                  (iota 16))))
    (test-case "an enabled open offer is satisfied by a different assigned value"
      (let* ((program
              (relational-choice-program
                (relation fixed (key value) '((42 #f)))
                (choice status (key value))
                (rule (closed (status ?key) (?value)) (fixed ?key ?value))
                (rule (open (status 42) #t))
                (limits 16 16 16)))
             (models (relational-choice-solve program state-budget: 4)))
        (check-equal? (length models) 1)
        (check-equal? (relational-program-query (car models) 'status) '((42 #f)))))
    (test-case "exhausted contradiction differs from exhaustion of a budget"
      (let (program
             (relational-choice-program
               (choice forbidden (key value))
               (rule (closed (forbidden 0) ()))
               (limits 8 8 8)))
        (check-equal? (relational-choice-solve program state-budget: 1) [])
        (check-exception (relational-choice-solve program state-budget: 0)
                         RelationalChoiceLimit?)))
    (test-case "closed intersection is deduced before scheduling optional choices"
      (let (program
             (relational-choice-program
               (choice color (node value))
               (rule (closed (color 0) (0 1)))
               (rule (closed (color 0) (1 2)))
               (rule (open (color 1) ?value) (color 0 ?value))
               (limits 16 16 16)))
        (check-equal? (model-colors (relational-choice-solve program state-budget: 3))
                      '(((0 . 1) (1 . 1))))
        (check-exception (relational-choice-solve program state-budget: 2)
                         RelationalChoiceLimit?)))
    (test-case "distinct named and anonymous body witnesses count as distinct grounding rows"
      (let* ((edges '((0 1) (0 2)))
             (make-program
              (lambda (limit)
                (relational-choice-program
                  (relation edge (from to) edges)
                  (choice color (node value))
                  (rule (open (color ?from) 1) (edge ?from ?to))
                  (rule (open (color ?from) 1) (edge ?from ?_))
                  (limits 8 limit 16)))))
        ;; Both rules have two grounded instances, although all four offer
        ;; the same value for the same attribute.
        (check-exception (relational-choice-solve (make-program 3) state-budget: 2) true)
        (check-equal? (model-colors (relational-choice-solve (make-program 4) state-budget: 2))
                      '(((0 . 1))))))
    (test-case "the exact distinct-state bound succeeds and a shorter budget raises"
      (let (program
            (relational-choice-program
              (choice color (node value))
              (rule (closed (color 0) (0 1 1)))
              (limits 8 8 8)))
        (check-equal? (length (relational-choice-solve program state-budget: 3)) 2)
        (check-exception (relational-choice-solve program state-budget: 2) RelationalChoiceLimit?)
        (check-exception (relational-choice-solve program state-budget: 0) RelationalChoiceLimit?)))
    (test-case "cancellation propagates from private grounding and stops final publication"
      (let ((program (choice-chain '((0 1) (1 2)))) (failure (list 'canceled)) (publications 0))
        (check-eq?
         (with-catch values
           (lambda ()
             (parameterize
               ((current-ascent-execution-control
                 (lambda (work facts)
                   (when (= work -1) (set! publications (+ publications 1)) (raise failure)))))
               (relational-choice-solve program state-budget: 64))))
         failure)
        (check-equal? publications 1)
        (check-eq?
         (with-catch values
           (lambda ()
             (parameterize
               ((current-ascent-execution-control
                 (lambda (work facts)
                   (when (= work 0) (raise failure)))))
               (relational-choice-solve program state-budget: 64))))
         failure)
        (check-equal? (length (relational-choice-solve program state-budget: 64)) 2)))
    (test-case "fact limits still reject a grounding run"
      (check-exception
       (relational-choice-solve
        (relational-choice-program
          (relation edge (from to) '((0 1) (0 2)))
          (choice color (node value))
          (rule (open (color ?node) 1) (edge 0 ?node))
          (limits 8 1 8))
        state-budget: 16)
       true))
    (test-case "functional choices are the sole writers and all heads are range restricted"
      (check-exception
       (relational-choice-program
         (choice color (node value))
         (rule (color 0 0))
         (limits 8 8 8))
       true)
      (check-exception
       (relational-choice-solve
        (relational-choice-program
          (choice color (node value))
          (rule (open (color ?n) 1))
          (limits 8 8 8))
        state-budget: 8)
       true))))
