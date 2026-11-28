;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/api relational-choice-program relational-choice-solve
                 RelationalChoiceLimit? relational-program-query relational-program
                 relational-program-session-run relational-program-append-source!)
        (only-in :gerbil-ascent/program/scheme-session relational-open-program-session/choice)
        (only-in :gerbil-ascent/program/scheme-query relational-program-solution-result
                 make-relational-program-solution)
        (only-in :gerbil-ascent/program/result gerbil-ascent-materialize-result)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control)
        (only-in :gerbil-ascent/program/scheme-choice call-with-relational-choice-measurement
                 make-relational-choice-head lower-relational-choice-program)
        (only-in :gerbil-ascent/program/func gerbil-ascent-atom gerbil-ascent-literal)
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
    (test-case "closed keys avoid enumerating equivalent assignment orders"
      (let* ((keys (iota 6))
             (program
              (relational-choice-program
                (relation node (key) (map list keys))
                (choice color (node value))
                (rule (closed (color ?key) (0 1)) (node ?key))
                (limits 32 32 32)))
             (expected
              (finite-choice-solutions
               (map (lambda (key) (list 'closed key '(0 1) [])) keys) void))
             (actual (model-colors (relational-choice-solve program state-budget: 127))))
        (check-equal? (length expected) 64)
        (check-equal? (length actual) (length expected))
        (check-equal? (andmap (lambda (model) (and (member model actual) #t)) expected) #t)
        (check-exception (relational-choice-solve program state-budget: 126)
                         RelationalChoiceLimit?)))
    (test-case "an open offer may need to wait for another key"
      (let* ((program
              (relational-choice-program
                (choice color (node value))
                (rule (open (color 1) 1))
                (rule (open (color 0) 0))
                (rule (open (color 0) 1) (color 1 1))
                (limits 16 16 16)))
             (expected (finite-choice-solutions
                        '((open 0 0 ()) (open 1 1 ()) (open 0 1 ((1 . 1)))) void))
             (actual (model-colors (relational-choice-solve program state-budget: 16))))
        (check-equal? (length actual) 2)
        (check-equal? (length actual) (length expected))
        (check-equal? (andmap (lambda (model) (and (member model actual) #t)) expected) #t)))
    (test-case "a new earlier closed offer preserves full-scan value and witness order"
      (let (program
             (relational-choice-program
               (choice color (node value))
               (rule (closed (color 0) (2 1)) (color 1 1))
               (rule (closed (color 0) (0 1 2)))
               (rule (closed (color 1) (1)))
               (limits 24 24 24)))
        (let*-values (((delta delta-work)
                       (call-with-relational-choice-measurement
                        (lambda () (relational-choice-solve program state-budget: 4))))
                      ((full _)
                       (call-with-relational-choice-measurement
                        (lambda () (relational-choice-solve program state-budget: 4)) #t)))
          (check-equal? (model-colors delta) '(((0 . 1) (1 . 1)) ((0 . 2) (1 . 1))))
          (check-equal? (model-colors delta) (model-colors full))
          (check-equal? (map (cut relational-program-query <> 'color provenance?: #t) delta)
                        (map (cut relational-program-query <> 'color provenance?: #t) full))
          (check (> (cdr (assq 'extensions delta-work)) 0) => #t))))
    (test-case "duplicate derived facts preserve ordered rows and choice witnesses"
      (let (program
            (relational-choice-program
              (relation value (item) '((1) (2) (3)))
              (relation derived (item))
              (choice gate (node value))
              (choice color (node value))
              (rule (closed (gate 0) (#t)))
              (rule (derived 1) (gate 0 #t))
              (rule (derived 1) (gate 0 #t))
              (rule (derived ?item) (gate 0 #t) (value ?item))
              (rule (closed (color ?item) (0)) (derived ?item))
              (limits 16 16 16)))
        (def (solve) (relational-choice-solve program state-budget: 8))
        (let*-values (((models _) (call-with-relational-choice-measurement solve))
                      ((reference _) (call-with-relational-choice-measurement solve 'direct)))
          (check-equal? (length models) 1)
          (let (rows (relational-program-query (car models) 'derived))
            (check-equal? (length rows) 3)
            (check (andmap (lambda (row) (and (member row rows) #t)) '((1) (2) (3))) => #t)
            (check-equal? rows (relational-program-query (car reference) 'derived)))
          (check-equal? (model-colors models) (model-colors reference))
          (check-equal? (relational-program-query (car models) 'color provenance?: #t)
                        (relational-program-query (car reference) 'color provenance?: #t)))))
    (test-case "a newly earlier singleton keeps its support when a multi-value offer was already installed"
      (let (program
            (relational-choice-program
              (choice color (node value))
              (choice gate (node value))
              (rule (closed (color 0) (2)) (gate 0 #t))
              (rule (closed (color 0) (1 2 1)))
              (rule (closed (gate 0) (#t)))
              (limits 16 16 16)))
        (def (solve) (relational-choice-solve program state-budget: 4))
        (let*-values (((models _) (call-with-relational-choice-measurement solve))
                      ((reference _) (call-with-relational-choice-measurement solve #t)))
          (check-equal? (model-colors models) '(((0 . 2))))
          (let ((actual (relational-program-query (car models) 'color provenance?: #t))
                (expected (relational-program-query (car reference) 'color provenance?: #t)))
            (check-equal? actual expected)
            (check-equal? (length (caddr (car actual))) 2)))))
    (test-case "a saved parent is scoped to one live session and branch identity"
      (let* ((program (relational-program (relation input (value) '((1))) (limits 8 8 8)))
             (left #f) (right #f) (save #f)
             (branch (list 'parent))
             (first (relational-open-program-session/choice program
                      (lambda (_ capture restore) (set! save capture) (set! left restore))))
             (second (relational-open-program-session/choice program
                       (lambda (_ _capture restore) (set! right restore)))))
        (relational-program-session-run first)
        (relational-program-session-run second)
        (let (saved (save branch))
          (check (and saved #t) => #t)
          (check-exception (left saved (list 'parent)) true)
          (check-exception (right saved branch) true)
          (left saved branch)
          (check-equal? (relational-program-query (relational-program-session-run first) 'input)
                        '((1))))))
    (test-case "restored Set membership deduplicates first writes and charges frozen rows"
      (let* ((program (relational-program
                        (relation input (owner value) '((0 11)))
                        (relation output (value))
                        (rule (output ?value) (input ?owner ?value))
                        (limits 8 2 12)))
             (branch (list 'parent))
             (save #f) (restore #f)
             (session (relational-open-program-session/choice program
                        (lambda (_ capture restorer)
                          (set! save capture)
                          (set! restore restorer)) #t)))
        (def (run) (relational-program-solution-result (relational-program-session-run session)))
        (def (rows result)
          (relational-program-query
           (make-relational-program-solution (gerbil-ascent-materialize-result result)) 'output))
        (let* ((initial (run)) (saved (save branch)))
          (check (and saved #t) => #t)
          (check-equal? (rows (restore saved branch)) '((11)))
          (relational-program-append-source! session 'input '(1 11))
          (check-equal? (rows (run)) '((11)))
          (relational-program-append-source! session 'input '(2 13))
          (check-equal? (rows (run)) '((11) (13)))
          (relational-program-append-source! session 'input '(3 17))
          (check-exception (run) true)
          (check-equal? (rows (run)) '((11) (13)))
          (check-equal? (rows (restore saved branch)) '((11)))
          (relational-program-append-source! session 'input '(4 19))
          (check-equal? (rows (run)) '((11) (19))))))
    (test-case "late model projection and repeated parent restore use their own frozen roots"
      (let* ((program (relational-program
                        (relation input (value) '((1) (2)))
                        (relation output (value))
                        (rule (output ?value) (input ?value))
                        (limits 12 12 24)))
             (branch (list 'parent))
             (save #f) (restore #f)
             (session (relational-open-program-session/choice program
                        (lambda (_ capture restorer)
                          (set! save capture)
                          (set! restore restorer)) #t)))
        (def (output result)
          (relational-program-query
           (make-relational-program-solution (gerbil-ascent-materialize-result result)) 'output))
        (let* ((parent (relational-program-solution-result (relational-program-session-run session)))
               (saved (save branch)))
          (check (and saved #t) => #t)
          (relational-program-append-source! session 'input '(3))
          (let (first (relational-program-solution-result (relational-program-session-run session)))
            (restore saved branch)
            (relational-program-append-source! session 'input '(4))
            (let (second (relational-program-solution-result (relational-program-session-run session)))
              (restore saved branch)
              (check-equal? (output second) '((1) (2) (4)))
              (check-equal? (output first) '((1) (2) (3)))
              (check-equal? (output parent) '((1) (2)))
              (check-equal?
               ((.ref (gerbil-ascent-materialize-result parent) 'relation-sizes))
               '((input . 2) (output . 2)))
              (set-car! (car (output first)) 100)
              (check-equal? (output first) '((1) (2) (3)))
              (check-equal? (output (restore saved branch)) '((1) (2))))))))
    (test-case "a full parent cache allowance still enumerates all models"
      (let (program
             (relational-choice-program
               (relation static (value) '((9)))
               (choice color (node value))
               (rule (closed (color 0) (0 1)))
               (limits 8 8 8)))
        (let-values (((models work)
                      (call-with-relational-choice-measurement
                       (lambda () (relational-choice-solve program state-budget: 3)))))
          (check-equal? (length models) 2)
          (check-equal? (cdr (assq 'parent-captures work)) 0)
          (check-equal? (cdr (assq 'source-replacements work)) 1)
          (check-exception (relational-choice-solve program state-budget: 2)
                           RelationalChoiceLimit?))))
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
    (test-case "deduction records both grounded constraints and returns detached evidence"
      (let* ((program
              (relational-choice-program
                (relation left (node witness) '((0 7)))
                (relation right (node witness) '((0 8)))
                (choice color (node value))
                (rule (closed (color ?node) (0 1)) (left ?node ?_))
                (rule (closed (color ?node) (1 2)) (right ?node ?_))
                (rule (open (color 1) ?value) (color 0 ?value))
                (limits 16 16 16)))
             (model (car (relational-choice-solve program state-budget: 3)))
             (read-proof (lambda () (relational-program-query model 'color provenance?: #t)))
             (proof (read-proof))
             (deduction (car proof))
             (supports (list-sort (lambda (a b) (< (car a) (car b))) (caddr deduction))))
        (check-equal? (map car proof) '(deduction branch))
        (check-equal? (map cadr proof) '((color 0 1) (color 1 1)))
        (check-equal? (map car supports) '(0 1))
        (check-equal? (map cadr supports) '(closed closed))
        (check-equal? (map cadddr supports) '(((left 0 7)) ((right 0 8))))
        (check-equal? (map (cut list-ref <> 4) supports) '((0 1) (1 2)))
        (check-equal? (vector? (caddr (car supports))) #t)
        (check-equal? (cadddr (car (caddr (cadr proof)))) '((color 0 1)))
        (set-car! (cadr deduction) 'altered)
        (set-car! (cadddr (car supports)) '(altered))
        (set-car! (list-ref (car supports) 4) 90)
        (vector-set! (caddr (car supports)) 0 #f)
        (check-equal? (cadr (car (read-proof))) '(color 0 1))
        (check-equal? (map cadddr (caddr (car (read-proof))))
                      (map (lambda (support) (if (= (car support) 0) '((left 0 7)) '((right 0 8))))
                           (caddr (car (read-proof)))))
        (check-equal? (relational-program-query model 'color) '((0 1) (1 1)))))
    (test-case "wide witness bindings preserve occurrence order and checkpoint charges"
      (let* ((program
              (relational-choice-program
                (relation seed (a b c d e f) '((1 2 3 4 5 6)))
                (relation tie (a b) '((6 1)))
                (choice color (node value))
                (rule (closed (color ?f) (?a))
                  (seed ?a ?b ?c ?d ?e ?f) (tie ?f ?a))
                (limits 16 16 16)))
             (model (car (relational-choice-solve program state-budget: 2)))
             (events [])
             (read (lambda () (relational-program-query model 'color provenance?: #t)))
             (receipt
              (parameterize ((current-ascent-execution-control
                              (lambda (work facts) (set! events (cons (cons work facts) events)))))
                (read)))
             (support (car (caddr (car receipt)))))
        (check-equal? (relational-program-query model 'color) '((6 1)))
        (check-equal? events '((1 . 0) (1 . 0) (1 . 0) (1 . 0)))
        (check-equal? (cadddr support) '((seed 1 2 3 4 5 6) (tie 6 1)))
        (check-equal? (list-ref support 4) '(1))
        (set-car! (cdr (car (cadddr support))) 100)
        (check-equal? (cadddr (car (caddr (car (read))))) '((seed 1 2 3 4 5 6) (tie 6 1)))))
    (test-case "each witness query detaches nested reader locations"
      (let* ((base
              (relational-program
                (relation input (value) '((5)))
                (relation color (node value))
                (limits 16 16 16)))
             (head (vector (string-copy "choice-source.ss") 11 19))
             (premise (vector (list 'input-source) 25))
             (program
              (lower-relational-choice-program base '(color)
                (list (make-relational-choice-head 'closed 'color
                        (list (gerbil-ascent-literal 0))
                        (list (gerbil-ascent-literal 1))
                        (list (gerbil-ascent-atom 'input (list (gerbil-ascent-literal 5))))
                        (vector head (list premise))))))
             (model (car (relational-choice-solve program state-budget: 2)))
             (read-origin
              (lambda ()
                (caddr (car (caddr (car (relational-program-query model 'color provenance?: #t))))))))
        (let* ((origin (read-origin))
               (head (vector-ref origin 0))
               (body (car (vector-ref origin 1))))
          (string-set! (vector-ref head 0) 0 #\X)
          (set-car! (vector-ref body 0) 'modified)
          (vector-set! head 1 -1)
          (vector-set! body 1 -2)
          (check-equal? (read-origin) '#(#("choice-source.ss" 11 19) (#((input-source) 25)))))))
    (test-case "each sibling keeps its own grounding support after replacement"
      (let* ((models (check-chain '((0 1) (1 2))))
             (proofs (map (lambda (model) (relational-program-query model 'color provenance?: #t)) models)))
        (for-each
         (lambda (model proof)
           (let (chosen (caddr (cadr (car proof))))
             (check-equal? (length proof) 3)
             (for-each
              (lambda (step)
                (check-equal? (caddr (cadr step)) chosen)
                (check-equal? (and (member (cdr (cadr step)) (relational-program-query model 'color)) #t) #t))
              proof)
             (for-each
              (lambda (step)
                (check-equal? (member `(color 0 ,chosen) (cadddr (car (caddr step))))
                              `((color 0 ,chosen) (path 0 ,(cadr (cadr step))))))
              (cdr proof)))) models proofs)))
    (test-case "open assignments reached in different orders consume one state per subset"
      (let (program
            (relational-choice-program
              (choice color (node value))
              (rule (open (color 0) 10))
              (rule (open (color 1) 11))
              (rule (open (color 2) 12))
              (rule (open (color 3) 13))
              (limits 16 16 16)))
        (let-values (((models work)
                      (call-with-relational-choice-measurement
                       (lambda () (relational-choice-solve program state-budget: 16)))))
          (check-equal? (model-colors models) '(((0 . 10) (1 . 11) (2 . 12) (3 . 13))))
          (check-equal? (cdr (assq 'states work)) 16)
          (let (witness (relational-program-query (car models) 'color provenance?: #t))
            (check-equal? (map car witness) '(branch branch branch branch))
            (check-equal? (length witness) 4)))
        (check-exception (relational-choice-solve program state-budget: 15) RelationalChoiceLimit?)))
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
