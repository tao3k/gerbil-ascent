;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :std/sync/completion make-completion completion-wait! completion-post!)
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
(def (wait-phase session phase)
  (let loop ((attempts 0))
    (unless (eq? (cadr (gerbil-ascent-session-state session)) phase)
      (when (= attempts 1000) (error "actor Session did not enter phase" phase))
      (thread-yield!) (loop (+ attempts 1)))))
(def (wait-running session) (wait-phase session 'running))

;; Pause at the first charged evaluation step to exercise in-flight control
;; independently of the time it takes to compute the fixture.
(def (start-paused-run session release)
  (let ((entered (make-completion)) (paused? #f))
    (def (observe work _facts)
      (when (and (> work 0) (not paused?))
        (set! paused? #t)
        (completion-post! entered #t)
        (completion-wait! release)))
    (def (run)
      (parameterize ((current-ascent-execution-control observe))
        (outcome (lambda () (gerbil-ascent-session-run session)))))
    (let (runner (spawn run))
      (completion-wait! entered)
      runner)))

(def (wait-until-blocked thread)
  (let loop ((remaining 1000))
    (unless (thread-state-waiting? (thread-state thread))
      (when (zero? remaining) (error "state caller did not suspend"))
      (thread-yield!)
      (loop (- remaining 1)))))
(def ascent-actor-session-test
  (test-suite "Session actor generation and completed publication"
    (test-case "affine replacement retires packed reuse without changing a held publication"
      (let* ((packed (map (lambda (i) (list (* 2 i) (+ (* 2 i) 1 (modulo i 2)))) (iota 32)))
             (first (map (lambda (i) (list (+ 100 i) (+ 101 i))) (iota 32)))
             (second (map (lambda (i) (list (+ 200 i) (+ 201 i))) (iota 32)))
             (x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
             (declaration
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'edge 2 packed) (gerbil-ascent-relation 'reach 2 []))
               (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y)))
                                       (list (gerbil-ascent-atom 'edge (list x y)))))
               32 32 64))
             (session (gerbil-ascent-open-actor-session declaration workers: 1)))
        (def (replace-with input)
          (gerbil-ascent-session-replace-source! session 'edge input)
          (rows (gerbil-ascent-session-run session)))
        (try
          (let (held (gerbil-ascent-session-run session))
            (check-equal? (replace-with first) first)
            (check-equal? (replace-with second) second)
            (let (exposed (replace-with packed))
              (check-equal? exposed packed)
              (set-car! (car exposed) -1)
              (check-equal? (rows held) packed)
              (check-equal? (rows (gerbil-ascent-session-last-completed session)) packed)))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "functional origin lanes preserve holes and retained source cuts"
      (let* ((dense (map (lambda (i)
                           (let (label (+ 200 i (quotient i 8))) (list label (+ label 1))))
                         (iota 32)))
             (sparse (map (lambda (i)
                            (let (label (+ 10000 (* 1024 i))) (list label (+ label 1))))
                          (iota 32)))
             (session (gerbil-ascent-open-actor-session (program dense) workers: 1)))
        (def (at result label)
          (let (found [])
            ((.ref result 'visit-rows) 'reach '(0) (list label)
              (lambda (row) (set! found (cons row found))))
            (reverse! found)))
        (try
          (let (before (gerbil-ascent-session-run session))
            (check-equal? (at before 206) '((206 208) (206 207)))
            (check-equal? (at before 208) [])
            (check-equal? (at before -1) [])
            (gerbil-ascent-session-replace-source! session 'edge sparse)
            (let (after (gerbil-ascent-session-run session))
              (check-equal? (at after 10000) '((10000 10001)))
              (check-equal? (at after 206) [])
              (check-equal? (at before 206) '((206 208) (206 207)))))
          (finally (gerbil-ascent-session-close! session)))))
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
    (test-case "retention checks current scalar cuts instead of retired declaration rows"
      (let* ((old-key (list 'initial))
             (new-key (list 'current))
             (x (gerbil-ascent-variable 'x))
             (declared
              (gerbil-ascent-program
               (list (gerbil-ascent-relation 'edge 1 (list (list old-key)))
                     (gerbil-ascent-relation 'reach 1 []))
               (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x)))
                                         (list (gerbil-ascent-atom 'edge (list x))))) 10 10 20))
             (session (gerbil-ascent-open-actor-session declared workers: 1))
             (work 0))
        (def (run)
          (set! work 0)
          (parameterize ((current-ascent-execution-control
                          (lambda (units _facts)
                            (when (> units 0) (set! work (+ work units))))))
            (rows (gerbil-ascent-session-run session))))
        (try
          (check-equal? (run) '(((initial))))
          (check-equal? (> work 0) #t)
          (gerbil-ascent-session-replace-source! session 'edge '((7)))
          (check-equal? (run) '((7)))
          (check-equal? (> work 0) #t)
          (check-equal? (run) '((7)))
          (check-equal? work 0)
          (gerbil-ascent-session-replace-source! session 'edge (list (list new-key)))
          (check-equal? (run) '(((current))))
          (set-car! new-key 'changed)
          (check-equal? (run) '(((changed))))
          (check-equal? (> work 0) #t)
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
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1)))))
            (release (make-completion)))
        (try
          (let* ((first (gerbil-ascent-session-run session))
                 (edges (map (lambda (n) (list n (+ n 1))) (iota 400))))
            (gerbil-ascent-session-replace-source! session 'edge edges)
            (let (runner (start-paused-run session release))
              (try
                (begin
                  (wait-running session)
                  (check-equal? (outcome (lambda () (gerbil-ascent-session-append-source! session 'edge '(8 9)))) 'rejected)
                  (check-equal? (gerbil-ascent-session-cancel! session) 'draining)
                  (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t))
                (finally (completion-post! release #t)))
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
      (let ((session (gerbil-ascent-open-actor-session (program (map (lambda (n) (list n (+ n 1))) (iota 400)))))
            (release (make-completion)))
        (let (runner (start-paused-run session release))
          (wait-running session)
          (let (closer (spawn (lambda () (gerbil-ascent-session-close! session) 'closed)))
            (try
              (wait-phase session 'draining)
              (finally (completion-post! release #t)))
            (check-equal? (thread-join! runner 3 'timeout) 'rejected)
            (check-equal? (thread-join! closer 3 'timeout) 'closed)
            (check-equal? (outcome (lambda () (gerbil-ascent-session-run session))) 'rejected)))))
    (test-case "replacement admission is atomic and caller mailbox is isolated"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)))))
        (try
         (thread-send (current-thread) 'caller-message)
         (check-equal? (outcome (lambda () (gerbil-ascent-session-replace-sources! session '((edge (3 4)) (reach (9)))))) 'rejected)
         (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1)))
         (check-equal? (thread-receive) 'caller-message)
         (finally (gerbil-ascent-session-close! session)))))
    (test-case "requests and closed failures preserve the caller selective-receive cursor"
      (thread-join!
       (spawn
        (lambda ()
          (let ((session (gerbil-ascent-open-actor-session (program '((0 1)))))
                (closed? #f))
            (try
              (thread-send (current-thread) 'first-marker)
              (thread-send (current-thread) 'second-marker)
              (check-equal? (thread-mailbox-next) 'first-marker)
              (check-equal? (gerbil-ascent-session-state session) '(0 idle))
              (gerbil-ascent-session-close! session)
              (set! closed? #t)
              (check-equal? (outcome (lambda () (gerbil-ascent-session-state session))) 'rejected)
              (check-equal? (thread-mailbox-next) 'second-marker)
              (thread-mailbox-rewind)
              (check-equal? (thread-receive) 'first-marker)
              (check-equal? (thread-receive) 'second-marker)
              (finally
                (thread-mailbox-rewind)
                (unless closed? (gerbil-ascent-session-close! session)))))))))
    (test-case "compact and authority-bearing state replies own their public values"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)))))
        (try
          (let ((first (gerbil-ascent-session-state session))
                (control (lambda (_work _facts) (error "state must not execute any rules"))))
            (set-car! first 'caller-mutation)
            (check-equal? (gerbil-ascent-session-state session) '(0 idle))
            (parameterize ((current-ascent-execution-control control))
              (check-equal? (gerbil-ascent-session-state session) '(0 idle)))
            (gerbil-ascent-session-replace-source! session 'edge '((1 2)))
            (let (updated (gerbil-ascent-session-state session))
              (check-equal? updated '(1 idle))
              (parameterize ((current-ascent-execution-control control))
                (check-equal? (gerbil-ascent-session-state session) updated))))
          (finally (gerbil-ascent-session-close! session)))))
    (test-case "an abandoned state wait cannot recycle a pending reply"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))
            (entered (make-completion)) (release (make-completion)) (released? #f))
        (try
          (begin
            (check-equal? (gerbil-ascent-session-state session) '(0 idle))
            (let (writer
                  (spawn (lambda ()
                    (gerbil-ascent-session-replace-sources! session '((edge (2 3)))
                      (lambda (_)
                        (completion-post! entered #t)
                        (completion-wait! release)
                        #t)))))
              (completion-wait! entered)
              (let ((abandoned (spawn (lambda () (gerbil-ascent-session-state session))))
                    (abort (list 'abandon-pending-state)))
                (wait-until-blocked abandoned)
                ;; A raising Gambit interrupt does not finish its caller
                ;; handshake: the target exits and the handshake mutex is abandoned.
                (check-equal?
                  (with-catch
                    (lambda (failure)
                      (if (abandoned-mutex-exception? failure) 'abandoned
                        (raise failure)))
                    (lambda () (thread-interrupt! abandoned (lambda () (raise abort)))))
                  'abandoned)
                (check-equal?
                  (with-catch
                    (lambda (failure)
                      (if (and (uncaught-exception? failure)
                               (eq? abort (uncaught-exception-reason failure)))
                        'rejected (raise failure)))
                    (lambda () (thread-join! abandoned 3 'timeout)))
                  'rejected))
              (let (update
                    (spawn (lambda () (gerbil-ascent-session-replace-source! session 'edge '((4 5))))))
                (wait-until-blocked update)
                (let ((first (spawn (lambda () (gerbil-ascent-session-state session))))
                      (second (spawn (lambda () (gerbil-ascent-session-state session)))))
                  (wait-until-blocked first)
                  (wait-until-blocked second)
                  (completion-post! release #t)
                  (set! released? #t)
                  (check-equal? (rows (thread-join! writer 3 'timeout)) '((2 3)))
                  (check-equal? (thread-join! update 3 'timeout) (void))
                  (let ((one (thread-join! first 3 'timeout))
                        (two (thread-join! second 3 'timeout)))
                    (check-equal? one '(2 idle))
                    (check-equal? two '(2 idle))
                    (set-car! one -1)
                    (check-equal? two '(2 idle))
                    (check-equal? (gerbil-ascent-session-state session) '(2 idle)))))))
          (finally
            (unless released? (completion-post! release #t))
            (gerbil-ascent-session-close! session)))))
    (test-case "close drains a queued state request through its own completion"
      (let ((session (gerbil-ascent-open-actor-session (program '((0 1))) workers: 1))
            (entered (make-completion)) (release (make-completion)) (released? #f))
        (try
          (let (writer
                (spawn (lambda ()
                  (gerbil-ascent-session-replace-sources! session '((edge (2 3)))
                    (lambda (_)
                      (completion-post! entered #t)
                      (completion-wait! release)
                      #t)))))
            (completion-wait! entered)
            (let (closer (spawn (lambda () (gerbil-ascent-session-close! session) 'closed)))
              (wait-until-blocked closer)
              (let (reader (spawn (lambda ()
                      (outcome (lambda () (gerbil-ascent-session-state session))))))
                (wait-until-blocked reader)
                (completion-post! release #t)
                (set! released? #t)
                (check-equal? (rows (thread-join! writer 3 'timeout)) '((2 3)))
                (check-equal? (thread-join! closer 3 'timeout) 'closed)
                (check-equal? (thread-join! reader 3 'timeout) 'rejected))))
          (finally
            (unless released? (completion-post! release #t))
            (with-catch void (lambda () (gerbil-ascent-session-close! session)))))))
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
