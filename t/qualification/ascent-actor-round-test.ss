;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        :gerbil-ascent/program/actor-round
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program))
(export ascent-actor-round-test)
(def (rejected? thunk) (with-catch (lambda (_) #t) (lambda () (thunk) #f)))
(def (closure-program edges (limit 10000))
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)) (z (gerbil-ascent-variable 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges) (gerbil-ascent-relation 'reach 2 []))
     (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y)))
                              (list (gerbil-ascent-atom 'edge (list x y))))
           (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x z)))
                              (list (gerbil-ascent-atom 'reach (list x y))
                                    (gerbil-ascent-atom 'edge (list y z)))))
     10000 limit 20000)))
(def (canonical result)
  (list-sort (lambda (a b) (or (< (car a) (car b)) (and (= (car a) (car b)) (< (cadr a) (cadr b)))))
             ((.ref result 'rows-of) 'reach)))
(def ascent-actor-round-test
  (test-suite "Positive actor rounds and drain barrier"
    (test-case "false first failure survives later worker cleanup failures"
      (let ((drained 0) (completed #f) (lock (make-mutex)))
        (check-equal?
         (with-catch (lambda (exception) (eq? exception #f))
          (lambda ()
            (gerbil-ascent-run-actor-round! (vector 'false-failure) '(a b c) 2
             (lambda (task emit! checkpoint!)
               (try (for-each (lambda (n) (emit! task (list n))) (iota 64))
                    (finally
                     (mutex-lock! lock) (set! drained (+ drained 1)) (mutex-unlock! lock)
                     (raise 'later-cleanup-failure))))
             (lambda (_ row) (raise #f)) (lambda () #f) (lambda (_) #t)
             (lambda (_) (set! completed #t))) #f)) #t)
        (check-equal? drained 2)
        (check-equal? completed #f)))
    (test-case "completion observes every row across final batch boundaries"
      (for-each
       (lambda (size)
         (let (rows [])
           (gerbil-ascent-run-actor-round! (vector size) '(a) 1
            (lambda (task emit! checkpoint!)
              (for-each (lambda (n) (emit! task (list n))) (iota size)))
            (lambda (_ row) (set! rows (cons (car row) rows)))
            (lambda () #f) (lambda (_) #t)
            (lambda (_) (check-equal? (reverse rows) (iota size))))
           (check-equal? (reverse rows) (iota size)))) '(0 1 31 32 33 64 65)))
    (test-case "coordinator callback faults refuse credit and preserve first failure"
      (for-each
       (lambda (control)
         (let ((phase (car control)) (size (cadr control)) (failure (vector control)) (started []) (drained []) (checks 0)
               (lock (make-mutex)))
           (check-equal?
            (with-catch (lambda (exception) (eq? exception failure))
             (lambda ()
               (gerbil-ascent-run-actor-round! (vector phase) '(a b c d) 2
                (lambda (task emit! checkpoint!)
                  (mutex-lock! lock) (set! started (cons task started)) (mutex-unlock! lock)
                  (try (for-each (lambda (n) (checkpoint!) (emit! task (list n))) (iota size))
                       (finally (mutex-lock! lock) (set! drained (cons task drained)) (mutex-unlock! lock))))
                (lambda (_ row) (when (eq? phase 'merge) (raise failure)))
                (lambda ()
                  (set! checks (+ checks 1))
                  (when (and (eq? phase 'cancel) (= checks 3)) (raise failure)) #f)
                (lambda (task) (when (and (eq? phase 'ready) (eq? task 'c)) (raise failure)) #t)
                (lambda (_) (when (eq? phase 'completed) (raise failure)))) #f)) #t)
           (check-equal? (length started) 2)
           (check-equal? (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) drained)
                         '(a b))))
       '((ready 1) (ready 96) (merge 1) (merge 96)
         (completed 1) (completed 96) (cancel 1) (cancel 96))))
    (test-case "refused credit bypasses task exception handlers and unwinds cleanup"
      (let ((caught #f) (returned #f) (drained #f))
        (check-equal?
         (rejected? (lambda ()
          (gerbil-ascent-run-actor-round! (vector 'stop-boundary) '(a b) 1
           (lambda (task emit! checkpoint!)
             (try
              (with-catch (lambda (_) (set! caught #t))
                (lambda () (for-each (lambda (n) (emit! task (list n))) (iota 64))))
              (set! returned #t)
              (finally (set! drained #t))))
           (lambda (_ row) (error "planned refusal"))))) #t)
        (check-equal? caught #f)
        (check-equal? returned #f)
        (check-equal? drained #t)))
    (test-case "one worker is reused and joined after all tasks"
      (let ((workers []) (completed []))
        (gerbil-ascent-run-actor-round! (vector 'reuse) '(a b c d) 1
         (lambda (task emit! checkpoint!)
           (set! workers (cons (current-thread) workers)) (emit! task '(1)))
         (lambda (_ row) (void)) (lambda () #f) (lambda (_) #t)
         (lambda (task) (set! completed (cons task completed))))
        (check-equal? completed '(d c b a))
        (check-equal? (andmap (lambda (worker) (eq? worker (car workers))) workers) #t)
        (check-equal? (thread-join! (car workers) 0 'alive) 'finished)))
    (test-case "failure after reuse preserves the exception and closes the pool"
      (let ((workers []) (completed []) (failure (vector 'planned)))
        (check-equal?
         (with-catch (lambda (exception) (eq? exception failure))
          (lambda ()
            (gerbil-ascent-run-actor-round! (vector 'reuse-failure) '(a b c) 1
             (lambda (task emit! checkpoint!)
               (set! workers (cons (current-thread) workers))
               (when (eq? task 'b) (raise failure)) (emit! task '(1)))
             (lambda (_ row) (void)) (lambda () #f) (lambda (_) #t)
             (lambda (task) (set! completed (cons task completed)))) #f)) #t)
        (check-equal? completed '(a))
        (check-equal? (length workers) 2)
        (check-equal? (eq? (car workers) (cadr workers)) #t)
        (check-equal? (thread-join! (car workers) 0 'alive) 'finished)))
    (test-case "joining monitor detects a worker that exits without completion"
      (check-equal?
       (rejected? (lambda ()
                   (gerbil-ascent-run-actor-round! (vector 'terminated) '(a b) 1
                    (lambda (_ emit! checkpoint!) (thread-terminate! (current-thread)))
                    (lambda (_ row) (void))))) #t))
    (test-case "ready admission preserves blocked prefixes and caller task spines"
      (let* ((tasks '(later first last)) (done []) (started []))
        (gerbil-ascent-run-actor-round! (vector 'dependencies) tasks 4
         (lambda (task emit! checkpoint!) (emit! task '(1)))
         (lambda (task row) (set! started (cons task started)))
         (lambda () #f)
         (lambda (task)
           (case task
             ((first) #t)
             ((later) (memq 'first done))
             ((last) (memq 'later done))))
         (lambda (task) (set! done (cons task done))))
        (check-equal? (reverse started) '(first later last))
        (check-equal? tasks '(later first last))))
    (test-case "identity aliases admit once and equal distinct tasks both execute"
      (let* ((a (vector 1)) (b (vector 1)) (tasks (list a a b a b)) (started []))
        (gerbil-ascent-run-actor-round! (vector 'aliases) tasks 1
         (lambda (task emit! checkpoint!) (emit! task '(1)))
         (lambda (task row) (set! started (cons task started))))
        (check-equal? (length started) 2)
        (check-equal? (eq? (car started) b) #t)
        (check-equal? (eq? (cadr started) a) #t)
        (check-equal? (map (lambda (task) (eq? task a)) tasks) '(#t #t #f #t #f))))
    (test-case "wide ready tasks are neither lost nor assigned twice"
      (let ((tasks (iota 256)) (seen (make-hash-table-eq))
            (workers (make-hash-table-eq)) (lock (make-mutex)))
        (gerbil-ascent-run-actor-round! (vector 'wide) tasks 16
         (lambda (task emit! checkpoint!)
           (mutex-lock! lock) (hash-put! workers (current-thread) #t) (mutex-unlock! lock)
           (emit! task '(1)))
         (lambda (task row)
           (when (hash-get seen task) (error "duplicate assignment" task))
           (hash-put! seen task #t)))
        (check-equal? (andmap (lambda (task) (hash-get seen task)) tasks) #t)
        (check-equal? (<= (length (hash-keys workers)) 16) #t)
        (for-each (lambda (worker) (check-equal? (thread-join! worker 0 'alive) 'finished))
                  (hash-keys workers))))
    (test-case "two workers rendezvous before owner merge"
      (let ((peer #f) (lock (make-mutex)) (merged []))
        (gerbil-ascent-run-actor-round! (vector 'round) '(a b) 2
         (lambda (task emit! checkpoint!)
           (mutex-lock! lock)
           (if peer
             (begin (thread-send peer 'ready) (mutex-unlock! lock))
             (begin (set! peer (current-thread)) (mutex-unlock! lock)
                    (unless (eq? (thread-receive 1 'timeout) 'ready) (error "workers did not overlap"))))
           (emit! task '(1)))
         (lambda (atom row) (set! merged (cons atom merged))))
        (check-equal? (length merged) 2)))
    (test-case "many batches preserve each private task stream"
      (let (rows [])
        (gerbil-ascent-run-actor-round! (vector 'stream) '(a b) 2
         (lambda (task emit! checkpoint!)
           (for-each (lambda (n) (checkpoint!) (emit! task (list n))) (iota 100)))
         (lambda (task row) (set! rows (cons (cons task row) rows))))
        (for-each (lambda (task)
                    (check-equal? (map cadr (filter (lambda (r) (eq? (car r) task)) (reverse rows))) (iota 100))) '(a b))))
    (test-case "merge failure drains and stops pending admission"
      (let ((started []) (terminated []) (lock (make-mutex)))
        (check-equal?
         (rejected? (lambda ()
          (gerbil-ascent-run-actor-round! (vector 'failure) '(a b c d) 2
           (lambda (task emit! checkpoint!)
             (mutex-lock! lock) (set! started (cons task started)) (mutex-unlock! lock)
             (try (for-each (lambda (n) (checkpoint!) (emit! task (list n))) (iota 1000))
                  (finally (mutex-lock! lock) (set! terminated (cons task terminated)) (mutex-unlock! lock))))
           (lambda (_ row) (error "planned merge failure"))))) #t)
        (check-equal? (length started) 2)
        (check-equal? (length terminated) 2)))
    (test-case "cancellation at checkpoints drains non-emitting workers"
      (let ((checks 0) (terminated 0) (lock (make-mutex)))
        (check-equal?
         (rejected? (lambda ()
          (gerbil-ascent-run-actor-round! (vector 'cancel) '(a b c) 2
           (lambda (task emit! checkpoint!)
             (try (for-each (lambda (_) (checkpoint!)) (iota 10000))
                  (finally (mutex-lock! lock) (set! terminated (+ terminated 1)) (mutex-unlock! lock))))
           (lambda (_ row) (error "unexpected candidate"))
           (lambda () (set! checks (+ checks 1)) (> checks 2))))) #t)
        (check-equal? terminated 2)))
    (test-case "recursive closure equals independent graph truth for one two four workers"
      (for-each
       (lambda (n)
         (let* ((edges (map (lambda (k) (list k (+ k 1))) (iota n)))
                (program (closure-program edges))
                (truth (apply append (map (lambda (a) (map (lambda (b) (list a b)) (iota (- (+ n 1) (+ a 1)) (+ a 1)))) (iota n)))))
           (for-each (lambda (jobs) (check-equal? (canonical (gerbil-ascent-evaluate-program program workers: jobs)) truth)) '(1 2 4)))) '(1 4 33)))
    (test-case "each frozen round has independent expected candidates"
      (let ((total '(1)) (round 0))
        (let loop ()
          (let ((frozen total) (pending []))
            (gerbil-ascent-run-actor-round! (vector 'round round frozen) '(a b) 2
             (lambda (task emit! checkpoint!)
               (case task
                 ((a) (when (memv 1 frozen) (emit! 'out '(2))))
                 ((b) (when (memv 2 frozen) (emit! 'out '(3))))))
             (lambda (_ row) (unless (or (memv (car row) total) (memv (car row) pending))
                               (set! pending (cons (car row) pending)))))
            (check-equal? (list-sort < pending) (case round ((0) '(2)) ((1) '(3)) (else [])))
            (unless (null? pending)
              (set! total (append total pending)) (set! round (+ round 1)) (loop))))))
    (test-case "parallel merge enforces unique derived budget"
      (for-each (lambda (jobs)
                  (check-equal? (rejected? (lambda () (gerbil-ascent-evaluate-program (closure-program '((0 1) (1 2)) 2) workers: jobs))) #t)) '(1 2 4)))
    (test-case "callback rules retain serial execution and trace"
      (let ((events []))
        (let* ((x (gerbil-ascent-variable 'x))
               (program (gerbil-ascent-program
                         (list (gerbil-ascent-relation 'input 1 '((1) (2)))
                               (gerbil-ascent-relation 'out 1 []))
                         (list (gerbil-ascent-rule
                                (list (gerbil-ascent-atom 'out (list x)))
                                (list (gerbil-ascent-atom 'input (list x))
                                      (gerbil-ascent-guard '(x) (lambda (n) (set! events (cons n events)) #t)))))
                         16 16 32)))
          (gerbil-ascent-evaluate-program program)
          (let (serial events)
            (set! events [])
            (gerbil-ascent-evaluate-program program workers: 4)
            (check-equal? events serial)))))
    (test-case "private mailbox preserves caller messages and worker failure is drained"
      (thread-send (current-thread) 'unrelated)
      (check-equal? (rejected? (lambda () (gerbil-ascent-run-actor-round! (vector 'bad) '(a) 2
                        (lambda (_ emit! checkpoint!) (error "planned worker failure")) (lambda (_ row) (void))))) #t)
      (check-equal? (thread-receive) 'unrelated))))
