;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil/runtime/gambit call-with-output-string display-exception)
        (only-in :gerbil-ascent/program/source-cut
                 gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows
                 gerbil-ascent-source-cut-update gerbil-ascent-source-cut-scalar?
                 gerbil-ascent-source-cut-initial-lane source-slot-newest-first source-slot-count)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/core/execution-control current-ascent-execution-control)
        :gerbil-ascent/program/func
        :gerbil-ascent/program/session
        :gerbil-ascent/program/actor-session)
(export ascent-actor-session-test)
(def (outcome call) (with-catch (lambda (_) 'rejected) call))
(def (diagnostic call)
  (with-catch
   (lambda (failure)
     (call-with-output-string (lambda (port) (display-exception failure port))))
   (lambda () (call) "accepted")))
(def (program edges (budget 200000) (input-budget 1000))
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)) (z (gerbil-ascent-variable 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges) (gerbil-ascent-relation 'reach 2 []))
     (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y))) (list (gerbil-ascent-atom 'edge (list x y))))
           (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x z)))
                              (list (gerbil-ascent-atom 'reach (list x y)) (gerbil-ascent-atom 'edge (list y z)))))
     input-budget budget 400000)))
(def (rows result) ((.ref result 'rows-of) 'reach))
(def (wait-running session)
  (let loop ((attempts 0))
    (unless (eq? (cadr (gerbil-ascent-session-state session)) 'running)
      (when (= attempts 1000) (error "actor Session did not start"))
      (thread-yield!) (loop (+ attempts 1)))))
(def ascent-actor-session-test
  (test-suite "Session actor generation and completed publication"
    (test-case "unchanged scalar cuts reuse private closure and refresh publication"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1) (1 2))) workers: 1))
            (work 0))
        (def (run)
          (set! work 0)
          (parameterize ((current-ascent-execution-control
                          (lambda (units facts) (when (> units 0) (set! work (+ work units))))))
            (gerbil-ascent-session-run session)))
        (try
          (let* ((first (run)) (expected (rows first)))
            (check-equal? (> work 0) #t)
            (let (again (run))
              (check-equal? work 0)
              (check-equal? (eq? first again) #f)
              (check-equal? (rows again) expected))
            ;; Neither a derived row pair nor an exported outer pair can reach
            ;; the retained engine. Each public read owns its row spines.
            (let (exposed (rows first))
              (set-car! (car exposed) 999)
              (set-cdr! exposed []))
            (check-equal? (rows (run)) expected)
            (check-equal? work 0)
            (gerbil-ascent-session-append-source! session 'edge '(2 3))
            (let (changed (run))
              (check-equal? (> work 0) #t)
              (check-equal? (length (rows changed)) 6))
            (check-equal? (length (rows (run))) 6)
            (check-equal? work 0))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "a refused reused publication retires its private engine"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))
            (work 0))
        (try
          (let (first (gerbil-ascent-session-run session))
            (check-equal?
             (outcome (lambda ()
               (parameterize ((current-ascent-execution-control
                               (lambda (units facts)
                                 (when (= units -1) (error "refuse cached publication")))))
                 (gerbil-ascent-session-run session)))) 'rejected)
            (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)
            (parameterize ((current-ascent-execution-control
                            (lambda (units facts) (when (> units 0) (set! work (+ work units))))))
              (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1))))
            (check-equal? (> work 0) #t))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "mutable literal keys cannot enter completed closure reuse"
      (let* ((key (list 'mutable))
             (x (gerbil-ascent-variable 'x))
             (declaration
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'edge 1 (list (list key)))
                     (gerbil-ascent-relation 'reach 1 []))
               (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x)))
                       (list (gerbil-ascent-atom 'edge (list x))))) 10 10 20))
             (session (gerbil-ascent-open-actor-session declaration workers: 1)))
        (try
          (gerbil-ascent-session-run session)
          (set-car! key 'changed)
          (let (work 0)
            (parameterize ((current-ascent-execution-control
                            (lambda (units facts) (when (> units 0) (set! work (+ work units))))))
              (check-equal? (rows (gerbil-ascent-session-run session)) '(((changed)))))
            (check-equal? (> work 0) #t))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "a reentrant acceptance checker refuses without waiting on itself"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))
            (reentered? #f))
        (try
          (check-equal?
           (outcome (lambda ()
             (parameterize ((current-ascent-execution-control
                             (lambda (units facts)
                               (when (= units -1)
                                 (set! reentered? #t)
                                 (gerbil-ascent-session-state session)))))
               (gerbil-ascent-session-run session)))) 'rejected)
          (check-equal? reentered? #t)
          (check-equal? (gerbil-ascent-session-last-completed session) #f)
          (check-equal? (cadr (gerbil-ascent-session-state session)) 'idle)
          (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "each run uses its caller execution authority before publishing"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))
            (checked? #f))
        (try
          (check-equal?
           (outcome
            (lambda ()
              (parameterize ((current-ascent-execution-control
                              (lambda (work facts)
                                (set! checked? #t)
                                (error "caller execution authority refused"))))
                (gerbil-ascent-session-run session))))
           'rejected)
          (check-equal? checked? #t)
          (check-equal? (gerbil-ascent-session-last-completed session) #f)
          (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "retired creation authority is not retained by a later run"
      (let* ((retired? #f)
             (session
              (parameterize ((current-ascent-execution-control
                              (lambda (work facts)
                                (when retired? (error "creation authority retired")))))
                (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))))
        (set! retired? #t)
        (try
          (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "refused final acceptance leaves the last completed cut untouched"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))
            (accepted? #f))
        (try
          (check-equal?
           (outcome
            (lambda ()
              (parameterize ((current-ascent-execution-control
                              (lambda (work facts)
                                (when (= work -1)
                                  (set! accepted? #t)
                                  (error "final acceptance refused")))))
                (gerbil-ascent-session-run session))))
           'rejected)
          (check-equal? accepted? #t)
          (check-equal? (gerbil-ascent-session-last-completed session) #f)
          (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "scalar cuts certify owned values across appends and replacements"
      (let* ((positions (make-hash-table-eq))
             (arity '#(1))
             (value (list 'mutable)))
        (hash-put! positions 'edge 1)
        (let* ((first (gerbil-ascent-make-source-cut positions arity '((edge (0)))))
               (mixed (gerbil-ascent-source-cut-update first positions arity
                        (list (list 'edge (list value))) #t 4))
               (again (gerbil-ascent-source-cut-update mixed positions arity
                        '((edge (1))) #f 4)))
          (check-equal? (gerbil-ascent-source-cut-scalar? first) #t)
          (check-equal? (gerbil-ascent-source-cut-scalar? mixed) #f)
          (check-equal? (gerbil-ascent-source-cut-scalar? again) #t)
          (check-equal? (gerbil-ascent-source-cut-rows first 0) '((0))))))
    (test-case "mutating an exported Actor row cannot change the next solve"
      (let* ((source '((0 1) (1 2)))
             (expected (rows (gerbil-ascent-evaluate-program (program source))))
             (session (gerbil-ascent-open-actor-session (program source) workers: 1)))
        (try
          (let* ((first (gerbil-ascent-session-run session))
                 (first-answers (rows first))
                 (exposed ((.ref first 'rows-of) 'edge)))
            (check-equal? (length first-answers) (length expected))
            (check-equal? (andmap (lambda (row) (if (member row first-answers) #t #f)) expected) #t)
            (set-car! (car exposed) 99)
            (set-cdr! exposed [])
            (check-equal? ((.ref first 'rows-of) 'edge) source)
            (check-equal? (rows (gerbil-ascent-session-run session)) first-answers))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "persistent source appends detach batches and share atomic ordered publication"
      (let ((positions (make-hash-table-eq)) (arities '#(1 1)))
        (hash-put! positions 'edge 1) (hash-put! positions 'other 2)
        (let* ((initial (gerbil-ascent-make-source-cut positions arities '((edge (0)) (other (7)))))
               (batch (list (list 1) (list 1) (list 2)))
               (middle (gerbil-ascent-source-cut-update initial positions arities (list (cons 'edge batch)) #t 10))
               (last (gerbil-ascent-source-cut-update middle positions arities '((edge (3))) #t 10)))
          (set-car! (car batch) 99)
          (set-cdr! batch [])
          (let* ((readers (map (lambda (_) (spawn (lambda () (gerbil-ascent-source-cut-rows last 0)))) (iota 8)))
                 (results (map thread-join! readers)))
            (for-each (lambda (rows)
                        (check-equal? rows '((0) (1) (1) (2) (3)))
                        (check-equal? (eq? rows (car results)) #t)) results))
          (check-equal? (gerbil-ascent-source-cut-rows middle 0) '((0) (1) (1) (2)))
          (check-equal? (gerbil-ascent-source-cut-rows initial 0) '((0)))
          (check-equal? (eq? (gerbil-ascent-source-cut-rows last 1)
                           (gerbil-ascent-source-cut-rows initial 1)) #t)
          (let* ((replaced (gerbil-ascent-source-cut-update last positions arities '((edge (8))) #f 10))
                 (empty (gerbil-ascent-source-cut-update replaced positions arities '((edge)) #t 10)))
            (check-equal? (gerbil-ascent-source-cut-rows empty 0) '((8)))
            (check-equal? (eq? (gerbil-ascent-source-cut-rows empty 0)
                             (gerbil-ascent-source-cut-rows replaced 0)) #t)
            (check-equal? (gerbil-ascent-source-cut-rows last 0) '((0) (1) (1) (2) (3)))))))
    (test-case "append prepends only new occurrences to the borrowed evaluator lane"
      (let ((positions (make-hash-table-eq)) (arities '#(1)))
        (hash-put! positions 'edge 1)
        (let* ((first (gerbil-ascent-make-source-cut positions arities '((edge (0) (1) (1)))))
               (next (gerbil-ascent-source-cut-update first positions arities
                       '((edge (1) (2))) #t 10))
               (replacement (gerbil-ascent-source-cut-update next positions arities
                              '((edge (0) (9) (1))) #f 10)))
          (let* ((old (gerbil-ascent-source-cut-initial-lane first 0))
                 (appended (gerbil-ascent-source-cut-initial-lane next 0))
                 (replaced (gerbil-ascent-source-cut-initial-lane replacement 0)))
            (check-equal? (source-slot-newest-first old) '((1) (1) (0)))
            (check-equal? (source-slot-count old) 3)
            (check-equal? (source-slot-newest-first appended) '((2) (1) (1) (1) (0)))
            (check-equal? (source-slot-count appended) 5)
            (check-equal? (eq? (cddr (source-slot-newest-first appended))
                               (source-slot-newest-first old)) #t)
            (check-equal? (source-slot-newest-first replaced) '((1) (9) (0)))
            (check-equal? (source-slot-count replaced) 3)))))
    (test-case "mixed source and multi-head writers retain exact source multiplicity"
      (let* ((x (gerbil-ascent-variable 'x))
             (program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'edge 1 '((1) (1) (2)))
                             (gerbil-ascent-relation 'mirror 1 [])
                             (gerbil-ascent-relation 'mixed 1 '((1) (1))))
                       (list (gerbil-ascent-rule
                              (list (gerbil-ascent-atom 'mirror (list x))
                                    (gerbil-ascent-atom 'mixed (list x)))
                              (list (gerbil-ascent-atom 'edge (list x)))))
                       100 100 100))
             (session (gerbil-ascent-open-actor-session program workers: 1)))
        (def (sorted result name)
          (list-sort < (map car ((.ref result 'rows-of) name))))
        (try
         (let (before (gerbil-ascent-session-run session))
           (check-equal? ((.ref before 'rows-of) 'edge) '((1) (1) (2)))
           (check-equal? (sorted before 'mirror) '(1 2))
           (check-equal? (sorted before 'mixed) '(1 1 2))
           (gerbil-ascent-session-append-source! session 'edge '(3))
           (let (after (gerbil-ascent-session-run session))
             (check-equal? ((.ref after 'rows-of) 'edge) '((1) (1) (2) (3)))
             (check-equal? (sorted after 'mirror) '(1 2 3))
             (check-equal? (sorted after 'mixed) '(1 1 2 3))
             (check-equal? (sorted before 'mixed) '(1 1 2))))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "foreign Program getters keep the staged source receiver"
      (let* ((base (program '((0 1))))
             (foreign (.o (:: @ base)
                        (max-output-facts
                         (let (sources (.ref @ 'relations))
                           (if (= (length (.ref (car sources) 'rows)) 1) 100 2)))))
             (session (gerbil-ascent-open-actor-session foreign workers: 1)))
        (try
         (let (first (gerbil-ascent-session-run session))
           (check-equal? (rows first) '((0 1)))
           (gerbil-ascent-session-append-source! session 'edge '(1 2))
           (check-equal? (outcome (lambda () (gerbil-ascent-session-run session))) 'rejected)
           (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)
           (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1))))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "foreign relation metadata reads the staged rows"
      (let* ((observed [])
             (base (program '((0 1))))
             (relations (.ref base 'relations))
             (edge (.o (:: @ (car relations))
                     (field-predicates
                      (begin
                        (set! observed (cons (length (.ref @ 'rows)) observed))
                        []))))
             (declaration (gerbil-ascent-program
                           (cons edge (cdr relations)) (.ref base 'rules) 100 100 100))
             (session (gerbil-ascent-open-actor-session declaration workers: 1)))
        (try
         (gerbil-ascent-session-append-source! session 'edge '(1 2))
         (set! observed [])
         (check-equal? (length (rows (gerbil-ascent-session-run session))) 3)
         (check-equal? (and (memv 2 observed) #t) #t)
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "source budget refusal preserves validation order and source rows"
      (let* ((positions (make-hash-table-eq)) (arities '#(2 1)))
        (hash-put! positions 'edge 1) (hash-put! positions 'other 2)
        (let* ((cut (gerbil-ascent-make-source-cut positions arities
                     '((edge (0 1)) (other (7)))))
               (small (list (cons 'edge (make-list 10000 '(2 3)))))
               (large (list (cons 'edge (make-list 20000 '(2 3))))))
          (for-each
           (lambda (append?)
             (for-each
              (lambda (batch)
                (check-equal?
                 (if (string-contains
                      (diagnostic (lambda ()
                        (gerbil-ascent-source-cut-update cut positions arities batch append? 2)))
                      "input fact budget exceeded") #t #f) #t)
                (check-equal? (gerbil-ascent-source-cut-rows cut 0) '((0 1)))
                (check-equal? (gerbil-ascent-source-cut-rows cut 1) '((7))))
              (list small large))) '(#f #t))
          (check-equal?
           (if (string-contains
                (diagnostic (lambda ()
                  (gerbil-ascent-source-cut-update cut positions arities
                    '((edge (2 3)) (edge (4))) #f 0)))
                "invalid ASCENT actor Session source rows") #t #f) #t)
          (check-equal?
           (if (string-contains
                (diagnostic (lambda ()
                  (gerbil-ascent-source-cut-update cut positions arities
                    '((edge (2 3)) (edge (4 5))) #f 0)))
                "duplicate ASCENT actor Session replacement") #t #f) #t)
          (let* ((row (list 4 5))
                 (next (gerbil-ascent-source-cut-update cut positions arities
                         (list (cons 'edge (list row))) #f 2)))
            (set-car! row 9)
            (check-equal? (gerbil-ascent-source-cut-rows next 0) '((4 5)))
            (check-equal? (gerbil-ascent-source-cut-rows next 1) '((7)))
            (check-equal? (gerbil-ascent-source-cut-rows cut 0) '((0 1)))))))
    (test-case "source preflight requires proper tuples and a finite outer list"
      (let* ((positions (make-hash-table-eq))
             (arities '#(2))
             (cyclic-row (list 1 2))
             (cyclic-rows (list '(1 2))))
        (hash-put! positions 'edge 1)
        (set-cdr! (cdr cyclic-row) cyclic-row)
        (set-cdr! cyclic-rows cyclic-rows)
        (let (cut (gerbil-ascent-make-source-cut positions arities '((edge (0 1)))))
          (for-each
           (lambda (invalid)
             (check-equal?
              (outcome (lambda ()
                (gerbil-ascent-source-cut-update cut positions arities
                  (list (cons 'edge invalid)) #f 2)))
              'rejected))
           (list '((1 2 . 3)) (list cyclic-row) cyclic-rows))
          (check-equal? (gerbil-ascent-source-cut-rows cut 0) '((0 1))))))
    (test-case "VM capacity default runs and invalid explicit capacities reject"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)))))
        (try
         (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
         (finally (gerbil-ascent-session-close! session))))
      (for-each
       (lambda (capacity)
         (check-equal? (outcome (lambda ()
                                 (gerbil-ascent-open-actor-session (program '((0 1))) workers: capacity)))
                       'rejected)) '(0 -1 1.5 #f)))
    (test-case "one two four workers match source updates and detached inputs"
      (for-each
       (lambda (jobs)
         (let (session (gerbil-ascent-open-actor-session (program '((0 1))) workers: jobs))
           (try
            (let (first (gerbil-ascent-session-run session))
              (check-equal? (rows first) '((0 1)))
              (let (row (list 1 2))
                (gerbil-ascent-session-append-source! session 'edge row)
                (set-car! row 99))
              (let (next (gerbil-ascent-session-run session))
                (check-equal?
                 (list-sort (lambda (a b) (or (< (car a) (car b)) (and (= (car a) (car b)) (< (cadr a) (cadr b))))) (rows next))
                 '((0 1) (0 2) (1 2)))
                (check-equal? (rows first) '((0 1)))
                (check-equal? (eq? next (gerbil-ascent-session-last-completed session)) #t))
              (gerbil-ascent-session-replace-sources! session '((edge (4 5)) (reach)))
              (check-equal? (rows (gerbil-ascent-session-run session)) '((4 5))))
            (finally (gerbil-ascent-session-close! session))))) '(1 2 4)))
    (test-case "cancel drains old work preserves publication and permits next generation"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)))))
        (try
         (let* ((first (gerbil-ascent-session-run session))
                (edges (map (lambda (n) (list n (+ n 1))) (iota 400))))
           (gerbil-ascent-session-replace-source! session 'edge edges)
           (let (runner (spawn (lambda () (outcome (lambda () (gerbil-ascent-session-run session))))))
             (wait-running session)
             (check-equal? (outcome (lambda () (gerbil-ascent-session-append-source! session 'edge '(8 9)))) 'rejected)
             (check-equal? (gerbil-ascent-session-cancel! session) 'draining)
             (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)
             (check-equal? (thread-join! runner 3 'timeout) 'rejected)
             (check-equal? (cadr (gerbil-ascent-session-state session)) 'idle)
             (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
             (check-equal? (> (car (gerbil-ascent-session-state session)) 2) #t)))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "duplicate derivations fit the exact budget and overflow cannot publish"
      (let* ((diamond '((0 1) (0 2) (1 3) (2 3)))
             (session (gerbil-ascent-open-actor-session (program diamond 5) workers: 1)))
        (try
         (let* ((first (gerbil-ascent-session-run session))
                (completed (rows first)))
           (check-equal? (length completed) 5)
           (for-each
            (lambda (row) (check-equal? (and (member row completed) #t) #t))
            (cons '(0 3) diamond))
           (gerbil-ascent-session-append-source! session 'edge '(3 4))
           (check-equal? (outcome (lambda () (gerbil-ascent-session-run session))) 'rejected)
           (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)
           (check-equal? (rows (gerbil-ascent-session-run session)) completed))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "hosted merge charges unique rows before one authorized publication"
      (let* ((diamond '((0 1) (0 2) (1 3) (2 3)))
             (session (gerbil-ascent-open-actor-session (program diamond 5) workers: 1))
             (charged 0)
             (publications 0))
        (def (run ceiling)
          (set! charged 0)
          (set! publications 0)
          (parameterize
              ((current-ascent-execution-control
                (lambda (work _facts)
                  (cond
                   ((= work -1) (set! publications (+ publications 1)))
                   ((positive? work)
                    (set! charged (+ charged work))
                    (when (> charged ceiling) (error "host work ceiling")))))))
            (gerbil-ascent-session-run session)))
        (try
          (let ((first (run 5))
                (replacement '((4 5) (4 6) (5 7) (6 7))))
            (check-equal? (length (rows first)) 5)
            (check-equal? (list charged publications) '(5 1))
            (gerbil-ascent-session-replace-source! session 'edge replacement)
            (check-equal? (outcome (lambda () (run 4))) 'rejected)
            (check-equal? (list charged publications) '(5 0))
            (check-equal? (eq? (gerbil-ascent-session-last-completed session) first) #t)
            (check-equal? (rows (run 5)) (rows first))
            (check-equal? (list charged publications) '(5 1)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "timed Actor returns and resumes the same private rounds as Session"
      (let* ((edges '((0 1) (1 2) (2 3) (3 4) (4 5)))
             (session (gerbil-ascent-open-actor-session (program '((90 91))) workers: 1))
             (reference (gerbil-ascent-open-session (program edges)))
             (prior-authority-live? #t)
             (complete-authorizations 0))
        (def (ordered result)
          (list-sort (lambda (left right)
                       (or (< (car left) (car right))
                           (and (= (car left) (car right)) (< (cadr left) (cadr right)))))
                     (rows result)))
        (try
          (let (prior (gerbil-ascent-session-run session))
            (gerbil-ascent-session-replace-source! session 'edge edges)
            (check-equal?
             (outcome (lambda () (gerbil-ascent-session-run-timeout session -1))) 'rejected)
            (let* ((first
                    (parameterize
                        ((current-ascent-execution-control
                          (lambda (work _facts)
                            (unless prior-authority-live? (error "expired partial authority"))
                            (when (= work -1)
                              (set! complete-authorizations (+ complete-authorizations 1))))))
                      (gerbil-ascent-session-run-timeout session 0)))
                   (other (gerbil-ascent-session-run-timeout reference 0)))
              (check-equal? (.ref first 'finished) #f)
              (check-equal? (ordered first) (ordered other))
              (check-equal? complete-authorizations 0)
              (check-equal? (eq? (gerbil-ascent-session-last-completed session) prior) #t)
              (set! prior-authority-live? #f)
              (let ((second (gerbil-ascent-session-run-timeout session 0))
                    (other (gerbil-ascent-session-run-timeout reference 0)))
                (check-equal? (.ref second 'finished) #f)
                (check-equal? (> (length (rows second)) (length (rows first))) #t)
                (check-equal? (ordered second) (ordered other)))
              (let ((final (gerbil-ascent-session-run session))
                    (other (gerbil-ascent-session-run reference)))
                (check-equal? (.ref final 'finished) #t)
                (check-equal? (ordered final) (ordered other))
                (check-equal? (length (rows final)) 15))))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "a source edit retires the unfinished Actor workspace"
      (let (session
             (gerbil-ascent-open-actor-session
              (program '((0 1) (1 2) (2 3) (3 4))) workers: 1))
        (try
          (check-equal? (.ref (gerbil-ascent-session-run-timeout session 0) 'finished) #f)
          (check-equal? (gerbil-ascent-session-last-completed session) #f)
          (gerbil-ascent-session-replace-source! session 'edge '((80 81)))
          (check-equal? (rows (gerbil-ascent-session-run session)) '((80 81)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "caller cancellation at partial delivery rolls back the Actor cut"
      (let ((session (gerbil-ascent-open-actor-session (program '((90 91))) workers: 1))
            (finished-worker? #f))
        (try
          (let (prior (gerbil-ascent-session-run session))
            (gerbil-ascent-session-replace-source! session 'edge
              '((0 1) (1 2) (2 3) (3 4)))
            (check-equal?
             (outcome (lambda ()
               (parameterize
                   ((current-ascent-execution-control
                     (lambda (work _facts)
                       (when (positive? work) (set! finished-worker? #t))
                       (when (and finished-worker?
                                  (eq? (thread-name (current-thread)) 'ascent-session-owner))
                         (error "host canceled partial delivery")))))
                 (gerbil-ascent-session-run-timeout session 0))))
             'rejected)
            (check-equal? finished-worker? #t)
            (check-equal? (eq? (gerbil-ascent-session-last-completed session) prior) #t)
            (check-equal? (rows (gerbil-ascent-session-run session)) '((90 91))))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "eager Actor replacement checks the complete candidate before adoption"
      (let* ((session (gerbil-ascent-open-actor-session (program '((90 91)) 3) workers: 1))
             (candidate '((edge (0 1) (1 2))))
             (acceptances 0))
        (def (accept? result)
          (set! acceptances (+ acceptances 1))
          (check-equal? (.ref result 'finished) #t)
          (check-equal? (length (rows result)) 3)
          (check-equal? (and (member '(0 2) (rows result)) #t) #t)
          #t)
        (try
          (let (prior (gerbil-ascent-session-run session))
            (check-equal?
             (outcome (lambda ()
               (gerbil-ascent-session-replace-sources! session candidate
                 (lambda (value) (accept? value) #f))))
             'rejected)
            (check-equal? acceptances 1)
            (check-equal? (eq? (gerbil-ascent-session-last-completed session) prior) #t)
            (check-equal?
             (outcome (lambda ()
               (gerbil-ascent-session-replace-sources! session
                 '((edge (0 1) (1 2) (2 3))) accept?)))
             'rejected)
            (check-equal? acceptances 1)
            (check-equal? (eq? (gerbil-ascent-session-last-completed session) prior) #t)
            (check-equal?
             (outcome (lambda ()
               (parameterize
                   ((current-ascent-execution-control
                     (lambda (work _facts)
                       (when (= work -1) (error "reject eager publication")))))
                 (gerbil-ascent-session-replace-sources! session candidate accept?))))
             'rejected)
            (check-equal? acceptances 2)
            (check-equal? (eq? (gerbil-ascent-session-last-completed session) prior) #t)
            (let (result (gerbil-ascent-session-replace-sources! session candidate accept?))
              (check-equal? acceptances 3)
              (check-equal? (eq? (gerbil-ascent-session-last-completed session) result) #t)
              (let (readback (gerbil-ascent-session-run-timeout session 0))
                (check-equal? (.ref readback 'finished) #t)
                (check-equal? (rows readback) (rows result)))))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "a failed indexed append drops tentative buckets before rollback"
      (let* ((key (gerbil-ascent-variable 'key))
             (value (gerbil-ascent-variable 'value))
             (source (map (lambda (id) (list 0 id)) (iota 32)))
             (program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'edge 2 source)
                             (gerbil-ascent-relation 'probe 1 '((0)))
                             (gerbil-ascent-relation 'left 1 [])
                             (gerbil-ascent-relation 'right 1 []))
                       (map (lambda (head)
                              (gerbil-ascent-rule (list (gerbil-ascent-atom head (list value)))
                                (list (gerbil-ascent-atom 'probe (list key))
                                      (gerbil-ascent-atom 'edge (list key value)))))
                            '(left right))
                       100 64 200))
             (session (gerbil-ascent-open-actor-session program workers: 1)))
        (def (check-result result)
          (check-equal? ((.ref result 'rows-of) 'edge) source)
          (for-each
           (lambda (head)
             (check-equal? (list-sort < (map car ((.ref result 'rows-of) head))) (iota 32)))
           '(left right)))
        (try
         (let (first (gerbil-ascent-session-run session))
           (check-result first)
           (gerbil-ascent-session-append-source! session 'edge '(0 32))
           (check-equal? (outcome (lambda () (gerbil-ascent-session-run session))) 'rejected)
           (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)
           (check-result (gerbil-ascent-session-run session))
           (check-result first))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "close during run cancels drains and rejects further requests"
      (let (session (gerbil-ascent-open-actor-session (program (map (lambda (n) (list n (+ n 1))) (iota 400)))))
        (let (runner (spawn (lambda () (outcome (lambda () (gerbil-ascent-session-run session))))))
          (wait-running session)
          (gerbil-ascent-session-close! session)
          (check-equal? (thread-join! runner 3 'timeout) 'rejected)
          (check-equal? (outcome (lambda () (gerbil-ascent-session-run session))) 'rejected))))
    (test-case "replacement admission is atomic and caller mailbox is isolated"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)))))
        (try
         (thread-send (current-thread) 'caller-message)
         (check-equal? (outcome (lambda () (gerbil-ascent-session-replace-sources! session '((edge (3 4)) (reach (9)))))) 'rejected)
         (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
         (check-equal? (thread-receive) 'caller-message)
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "batch rejection preserves generation sources and multiplicity budget"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)) 200000 2)))
        (try
         (gerbil-ascent-session-run session)
         (let (before (gerbil-ascent-session-state session))
           (for-each
            (lambda (batch)
              (check-equal? (outcome (lambda () (gerbil-ascent-session-replace-sources! session batch))) 'rejected)
              (check-equal? (gerbil-ascent-session-state session) before))
            '(((edge (3 4)) (edge (5 6)))
              ((edge (3 4)) (missing (5 6)))
              ((edge (3 4) (3 4)) (reach (7 8)))))
           (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1))))
         (gerbil-ascent-session-replace-source! session 'edge '((4 5) (4 5)))
         (check-equal? (outcome (lambda () (gerbil-ascent-session-append-source! session 'edge '(4 5)))) 'rejected)
         (check-equal? (rows (gerbil-ascent-session-run session)) '((4 5)))
         (gerbil-ascent-session-replace-sources! session '((edge) (reach (8 9))))
         (check-equal? (rows (gerbil-ascent-session-run session)) '((8 9)))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "initial and replacement row spines are owned across committed cuts"
      (let* ((input (list (list 0 1)))
             (session (gerbil-ascent-open-actor-session (program input))))
        (try
         (set-car! (car input) 99)
         (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
         (let ((replacement (list (list 3 4))) (batch-tail (list (list 7 8))))
           (gerbil-ascent-session-replace-sources! session
             (list (cons 'edge replacement) (cons 'reach batch-tail)))
           (set-car! replacement '(50 60))
           (set-car! (car batch-tail) 70)
           (check-equal? (list-sort (lambda (a b) (< (car a) (car b)))
                                  (rows (gerbil-ascent-session-run session))) '((3 4) (7 8))))
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "cancellation options reject incompatible timing and invalid predicates"
      (let (p (program '((0 1))))
        (check-equal? (outcome (lambda () (gerbil-ascent-evaluate-program p workers: 1
                                        measure-rule-times?: #t canceled?: (lambda () #f)))) 'rejected)
        (check-equal? (outcome (lambda () (gerbil-ascent-evaluate-program p canceled?: 10))) 'rejected)))
    (test-case "callbacks rejected before actor Session creation"
      (let* ((x (gerbil-ascent-variable 'x))
             (p (gerbil-ascent-program (list (gerbil-ascent-relation 'edge 1 '((1))))
                  (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'edge (list x)))
                      (list (gerbil-ascent-atom 'edge (list x)) (gerbil-ascent-guard '(x) (lambda (_) #t))))) 4 4 8)))
        (check-equal? (outcome (lambda () (gerbil-ascent-open-actor-session p))) 'rejected)))))
