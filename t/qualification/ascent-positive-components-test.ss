;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        :gerbil-ascent/program/actor-round
        :gerbil-ascent/program/positive-components
        (only-in :gerbil-ascent/t/performance/component-scope/fixture
                 component-scope-program component-scope-request component-scope-plan
                 component-scope-normalize component-scope-run)
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
    (test-case "output membership preserves seeded rows and leaves source-only roots intact"
      (let* ((x (gerbil-ascent-variable 'x))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'source 1 '((0) (1) (1)))
                       (gerbil-ascent-relation 'out 1 '((0)))
                       (gerbil-ascent-relation 'unused 1 '((7) (7))))
                 (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list x)))
                                           (list (gerbil-ascent-atom 'source (list x))))) 64 64 64))
             (request (component-scope-request p))
             (initial (vector-ref request 2)) (before (vector-copy initial)))
        (for-each
         (lambda (jobs)
           (let (emitted [])
             (gerbil-ascent-run-positive-components!
              (vector-ref request 0) (vector-ref request 1) initial jobs
              (lambda (atom row) (set! emitted (cons (cons (vector-ref atom 0) row) emitted)))
              (lambda () #f))
             (check-equal? emitted '((1 1)))
             (check-equal? initial before)
             (for-each (lambda (i) (check-equal? (eq? (vector-ref initial i) (vector-ref before i)) #t)) (iota 3))))
         '(1 2 4))))
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
    (test-case "plan cache shares only the exact immutable analysis identity"
      (let* ((p (program '((0 1))))
             (first (gerbil-ascent-make-engine p #t))
             (second (gerbil-ascent-make-engine p #t))
             (analysis (.ref first '.analysis))
             (cached (gerbil-ascent-positive-components analysis))
             (fresh (gerbil-ascent-positive-components (.ref (gerbil-ascent-make-engine (program '((1 2))) #t) '.analysis))))
        (check-equal? (eq? analysis (.ref second '.analysis)) #t)
        (check-equal? (eq? cached (gerbil-ascent-positive-components (.ref second '.analysis))) #t)
        (check-equal? (eq? cached fresh) #f)
        (check-equal? (canonical (gerbil-ascent-evaluate-program p workers: 2) 'reach) '((0 1)))
        (check-equal? (canonical (gerbil-ascent-evaluate-program (program '((1 2))) workers: 2) 'reach) '((1 2)))
        (check-equal? (eq? cached (gerbil-ascent-positive-components analysis)) #t)))
    (test-case "cached and freshly compiled plans retain identical projected rules"
      (let* ((p (program '((0 1) (1 2))))
             (analysis (.ref (gerbil-ascent-make-engine p #t) '.analysis))
             (cached (gerbil-ascent-positive-components analysis)))
        (def (shape components)
          (map (lambda (c) (list (positive-component-id c) (positive-component-members c)
                                (positive-component-rules c) (positive-component-predecessors c))) components))
        (check-equal? (shape cached) (shape (gerbil-ascent-compile-positive-components analysis)))
        ;; Planning-only paired control: native compilation versus a cache hit.
        ;; No timer threshold; every batch is checked before reporting.
        (for-each
         (lambda (modes)
           (for-each (lambda (mode)
             (let* ((start (current-jiffy))
                    (last (let loop ((left 100) (last #f))
                            (if (zero? left) last
                              (loop (- left 1) ((if (eq? mode 'cached) gerbil-ascent-positive-components gerbil-ascent-compile-positive-components) analysis)))))
                    (elapsed (- (current-jiffy) start)))
               (check-equal? (shape cached) (shape last))
               (displayln "SCC-PLAN-PROBE mode=" mode " repeats=100 jiffies=" elapsed " rate=" (jiffies-per-second))
               (force-output))) modes))
         '((fresh cached) (cached fresh) (fresh cached)))))
    (test-case "SCC projection shares admitted body slots and ordered output actions"
      (let* ((request (component-scope-request (component-scope-program 16 8 1 #t)))
             (full (vector-ref (car (vector-ref (vector-ref (vector-ref request 0) 5) 0)) 5))
             (components (component-scope-plan #f request)))
        (for-each
         (lambda (component)
           (for-each
            (lambda (rule)
              (let (plan (vector-ref rule 0))
                (check-equal? (eq? (vector-ref plan 1) (vector-ref full 1)) #t)
                (check-equal? (vector-ref plan 2) (vector-ref full 2))
                (for-each (lambda (output) (check-equal? (and (memq output (vector-ref full 0)) #t) #t))
                          (vector-ref plan 0)))) (positive-component-rules component))) components)
        (check-equal? (length (vector-ref full 0)) 16)))
    (test-case "full survivors retain plan identity and finite metadata matches baseline"
      (for-each
       (lambda (count)
         (for-each
          (lambda (multi?)
            (let* ((request (component-scope-request (component-scope-program count 4 1 multi?)))
                   (components (component-scope-plan #f request))
                   (full (map (lambda (rule) (vector-ref rule 5))
                              (car (vector->list (vector-ref (vector-ref request 0) 5))))))
              (check-equal? (component-scope-normalize #f components)
                            (component-scope-normalize #t (component-scope-plan #t request)))
              (unless multi?
                (for-each (lambda (component)
                            (for-each (lambda (rule) (check-equal? (and (memq (vector-ref rule 0) full) #t) #t))
                                      (positive-component-rules component))) components)))) '(#f #t))) '(1 4 16)))
    (test-case "duplicate and literal projected heads preserve independent truth"
      (let* ((x (gerbil-ascent-variable 'x))
             (p (gerbil-ascent-program
                 (list (gerbil-ascent-relation 'source 1 '((7)))
                       (gerbil-ascent-relation 'left 1 []) (gerbil-ascent-relation 'right 1 []))
                 (list (gerbil-ascent-rule
                        (list (gerbil-ascent-atom 'left (list x))
                              (gerbil-ascent-atom 'right (list x))
                              (gerbil-ascent-atom 'left (list (gerbil-ascent-literal 77)))
                              (gerbil-ascent-atom 'left (list x)))
                        (list (gerbil-ascent-atom 'source (list x))))) 64 64 64)))
        (for-each (lambda (jobs)
                    (let (result (gerbil-ascent-evaluate-program p workers: jobs))
                      (check-equal? (canonical result 'left) '((7) (77)))
                      (check-equal? (canonical result 'right) '((7))))) '(1 2 4))))
    (test-case "assigned SCC state preserves caller roots across independent runs"
      (let* ((request (component-scope-request (component-scope-program 4 1 32)))
             (initial (vector-ref request 2)) (before (vector-copy initial))
             (truth (make-vector 5 (map list (iota 32)))))
        (for-each (lambda (jobs)
                    (check-equal? (component-scope-run #f request jobs) truth)
                    (check-equal? initial before)
                    (for-each (lambda (index) (check-equal? (eq? (vector-ref initial index) (vector-ref before index)) #t))
                              (iota 5))) '(1 2 4))))
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
