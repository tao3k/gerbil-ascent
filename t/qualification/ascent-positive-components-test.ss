;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        :gerbil-ascent/program/actor-round
        :gerbil-ascent/program/positive-components
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine gerbil-ascent-evaluate-program))
(export ascent-positive-components-test)
(def (rejected? call) (with-catch (lambda (_) #t) (lambda () (call) #f)))
(def (program edges (limit 10000))
  (let ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)) (z (gerbil-ascent-variable 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges) (gerbil-ascent-relation 'reach 2 [])
           (gerbil-ascent-relation 'copy 2 []) (gerbil-ascent-relation 'joined 2 [])
           (gerbil-ascent-relation 'seed 1 '((7) (8))) (gerbil-ascent-relation 'out 1 []))
     (list
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y)) (gerbil-ascent-atom 'copy (list x y))) (list (gerbil-ascent-atom 'edge (list x y))))
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x z))) (list (gerbil-ascent-atom 'reach (list x y)) (gerbil-ascent-atom 'edge (list y z))))
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'joined (list x y))) (list (gerbil-ascent-atom 'reach (list x y)) (gerbil-ascent-atom 'copy (list x y))))
      (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list x))) (list (gerbil-ascent-atom 'seed (list x)))))
     10000 limit 20000)))
(def (canonical result name)
  (list-sort (lambda (a b) (or (< (car a) (car b)) (and (= (car a) (car b)) (pair? (cdr a)) (< (cadr a) (cadr b)))))
             ((.ref result 'rows-of) name)))
(def ascent-positive-components-test
  (test-suite "Ready positive SCCs and projected heads"
    (test-case "successor runs while an independent component remains assigned"
      (let ((peers (make-hash-table-eq)) (lock (make-mutex)) (done []) (merged []))
        (gerbil-ascent-run-actor-round! (vector 'dag) '(a b c) 2
         (lambda (task emit! checkpoint!)
           (case task
             ((a c)
              (mutex-lock! lock)
              (hash-put! peers task (current-thread))
              (let (peer (hash-get peers (if (eq? task 'a) 'c 'a)))
                (mutex-unlock! lock)
                (if peer (thread-send peer 'start)
                    (unless (eq? (thread-receive 1 'timeout) 'start) (error "independent tasks did not overlap"))))
              (if (eq? task 'a) (emit! 'a '(1))
                  (unless (eq? (thread-receive 1 'timeout) 'successor) (error "successor waited for independent component"))))
             ((b)
              (check-equal? merged '((a 1)))
              (thread-send (hash-get peers 'c) 'successor)
              (emit! 'b '(2)))))
         (lambda (atom row) (set! merged (append merged (list (cons atom row)))))
         (lambda () #f)
         (lambda (task) (or (not (eq? task 'b)) (memq 'a done)))
         (lambda (task) (set! done (cons task done))))
        (check-equal? (length done) 3)
        (check-equal? merged '((a 1) (b 2)))))
    (test-case "multi-head plans project into their exact relation SCC"
      (let* ((engine (gerbil-ascent-make-engine (program '((0 1))) #t))
             (components (gerbil-ascent-positive-components (.ref engine '.analysis))))
        (check-equal? (length components) 6)
        (check-equal? (apply + (map (lambda (c) (length (positive-component-rules c))) components)) 5)
        (for-each
         (lambda (component)
           (for-each (lambda (rule)
                       (for-each (lambda (output)
                                   (check-equal? (and (memv (vector-ref (vector-ref output 0) 0) (positive-component-members component)) #t) #t))
                                 (vector-ref (vector-ref rule 0) 0)))
                     (positive-component-rules component))) components)))
    (test-case "chain closure and independent outputs match exact truth one two four workers"
      (for-each
       (lambda (n)
         (let* ((edges (map (lambda (k) (list k (+ k 1))) (iota n)))
                (p (program edges))
                (truth (apply append (map (lambda (a) (map (lambda (b) (list a b)) (iota (- n a) (+ a 1)))) (iota n)))))
           (for-each
            (lambda (jobs)
              (let (result (gerbil-ascent-evaluate-program p workers: jobs))
                (check-equal? (canonical result 'reach) truth)
                (check-equal? (canonical result 'copy) edges)
                (check-equal? (canonical result 'joined) edges)
                (check-equal? (canonical result 'out) '((7) (8))))) '(1 2 4)))) '(1 4 33)))
    (test-case "recursive cycle reaches independent complete graph truth"
      (let* ((p (program '((0 1) (1 2) (2 0))))
             (truth (apply append (map (lambda (a) (map (lambda (b) (list a b)) '(0 1 2))) '(0 1 2)))))
        (for-each (lambda (jobs) (check-equal? (canonical (gerbil-ascent-evaluate-program p workers: jobs) 'reach) truth)) '(1 2 4))))
    (test-case "owner enforces unique global budget across independent components"
      ;; One edge produces reach/copy/joined plus two independent out facts.
      (for-each
       (lambda (jobs)
         (check-equal? (rejected? (lambda () (gerbil-ascent-evaluate-program (program '((0 1)) 4) workers: jobs))) #t)
         (check-equal? (canonical (gerbil-ascent-evaluate-program (program '((0 1)) 5) workers: jobs) 'out) '((7) (8)))) '(1 2 4)))
    (test-case "matched fresh solves retain exact truth before reporting timing"
      (let* ((n 64) (edges (map (lambda (k) (list k (+ k 1))) (iota n))) (p (program edges))
             (truth (apply append (map (lambda (a) (map (lambda (b) (list a b)) (iota (- n a) (+ a 1)))) (iota n)))))
        ;; Warm immutable analysis equally; every timed solve creates fresh state.
        (gerbil-ascent-evaluate-program p)
        (for-each
         (lambda (modes)
           (for-each
            (lambda (mode)
              (let* ((start (current-jiffy))
                     (result (if (eq? mode 'serial)
                               (gerbil-ascent-evaluate-program p)
                               (gerbil-ascent-evaluate-program p workers: mode canceled?: (lambda () #f))))
                     (elapsed (- (current-jiffy) start)))
                (check-equal? (canonical result 'reach) truth)
                (check-equal? (canonical result 'copy) edges)
                (check-equal? (canonical result 'joined) edges)
                (check-equal? (canonical result 'out) '((7) (8)))
                (displayln "SCC-PROBE mode=" mode " edges=" n " jiffies=" elapsed " rate=" (jiffies-per-second))
                (force-output))) modes))
         '((serial 1 2 4) (4 2 1 serial) (2 serial 4 1)))))
    (test-case "dependency deadlock rejects and ready predicate failure drains"
      (check-equal? (rejected? (lambda () (gerbil-ascent-run-actor-round! (vector 'blocked) '(a) 2
                              (lambda (_ emit! checkpoint!) (error "should not dispatch"))
                              (lambda (_ row) (void)) (lambda () #f) (lambda (_) #f)))) #t)
      (let (terminal #f)
        (check-equal? (rejected? (lambda ()
          (gerbil-ascent-run-actor-round! (vector 'bad-ready) '(a b) 2
           (lambda (_ emit! checkpoint!) (try (for-each (lambda (_) (checkpoint!)) (iota 10000)) (finally (set! terminal #t))))
           (lambda (_ row) (void)) (lambda () #f)
           (lambda (task) (if (eq? task 'b) (error "planned ready failure") #t))))) #t)
        (check-equal? terminal #t)))))
