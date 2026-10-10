;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :std/list/list append-map)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        :gerbil-ascent/program/actor-round
        :gerbil-ascent/program/positive-components
        (only-in :gerbil-ascent/program/component-worker make-component-snapshot gerbil-ascent-run-positive-component!)
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
    (test-case "completed snapshot merge preserves concurrently completed unrelated writes"
      (let ((worker #f) (captured #f) (published '((seed 0))) (completed []) (lock (make-mutex)))
        (gerbil-ascent-run-actor-round! (vector 'snapshot-frame) '(left right) 2
         (lambda (task emit! checkpoint!)
           (case task
             ((left)
              (mutex-lock! lock)
              (set! worker (current-thread))
              (let (ready? (memq 'right completed))
                (mutex-unlock! lock)
                (unless ready?
                  (unless (eq? (thread-receive 1 'timeout) 'published)
                    (error "unrelated completion failed to overlap frozen snapshot"))))
              (check-equal? captured '((seed 0)))
              (emit! 'left '(0)) (emit! 'left '(1)))
             ((right) (emit! 'right '(0)))))
         (lambda (atom row) (set! published (cons (cons atom row) published)))
         (lambda () #f)
         (lambda (task)
           (when (eq? task 'left) (set! captured (map values published))) #t)
         (lambda (task)
           (mutex-lock! lock)
           (set! completed (cons task completed))
           (let (target (and (eq? task 'right) worker))
             (mutex-unlock! lock)
             (when target (thread-send target 'published)))))
        (check-equal? (if (member '(right 0) published) #t #f) #t)
        (check-equal? (if (member '(left 0) published) #t #f) #t)
        (check-equal? (if (member '(left 1) published) #t #f) #t)
        (check-equal? (length published) 4)
        (check-equal? (length completed) 2)))
    (test-case "duplicate chunks and terminal tail preserve complete Set admission"
      (let ((known (make-hash-table)) (published []) (candidates 0) (completed []) (observed #f))
        (gerbil-ascent-run-actor-round! (vector 'duplicate-chunks) '(producer successor) 2
         (lambda (task emit! checkpoint!)
           (case task
             ((producer)
              ;; Two credited 32-row batches plus one terminal candidate.
              (for-each (lambda (n) (emit! 'producer (list (modulo n 17)))) (iota 65)))
             ((successor)
              (check-equal? candidates 65)
              (check-equal? (length published) 17)
              (for-each (lambda (n) (check-equal? (if (member (list n) published) #t #f) #t)) (iota 17))
              (set! observed #t))))
         (lambda (atom row)
           (set! candidates (+ candidates 1))
           (unless (hash-get known row)
             (hash-put! known row #t)
             (set! published (cons row published))))
         (lambda () #f)
         (lambda (task) (or (eq? task 'producer) (memq 'producer completed)))
         (lambda (task) (set! completed (cons task completed))))
        (check-equal? candidates 65)
        (check-equal? (length published) 17)
        (check-equal? observed #t)
        (check-equal? (length completed) 2)))
    (test-case "successor snapshot waits for terminal tail after credited predecessor batch"
      (let ((producer #f) (released? #f) (done []) (merged []) (snapshot #f))
        (gerbil-ascent-run-actor-round! (vector 'terminal-snapshot) '(a b) 2
         (lambda (task emit! checkpoint!)
           (case task
             ((a)
              (set! producer (current-thread))
              ;; The 32nd row yields a batch and waits for owner credit.
              (for-each (lambda (n) (emit! 'a (list n))) (iota 32))
              (unless (eq? (thread-receive 1 'timeout) 'finish)
                (error "owner did not observe credited predecessor batch"))
              (emit! 'a '(32)))
             ((b)
              (check-equal? (length snapshot) 33)
              (check-equal? (map cadr snapshot) (iota 33))
              (emit! 'b '(33)))))
         (lambda (atom row) (set! merged (append merged (list (cons atom row)))))
         (lambda () #f)
         (lambda (task)
           (if (eq? task 'a) #t
             (begin
               (when (and (= (length merged) 32) (not released?))
                 (check-equal? (memq 'a done) #f)
                 (set! released? #t)
                 (thread-send producer 'finish))
               (and (memq 'a done)
                    (begin (set! snapshot (map values merged)) #t)))))
         (lambda (task) (set! done (cons task done))))
        (check-equal? released? #t)
        (check-equal? (length merged) 34)
        (check-equal? (length snapshot) 33)
        (check-equal? (length done) 2)))
    (test-case "ground recursive diamond matches least closure under independent component orders"
      (def (atom relation numbers)
        (gerbil-ascent-atom relation (map gerbil-ascent-literal numbers)))
      (let* ((seed (gerbil-ascent-relation 'seed 1 '((0))))
             (left (gerbil-ascent-relation 'left 1 []))
             (right (gerbil-ascent-relation 'right 1 []))
             (out (gerbil-ascent-relation 'out 1 []))
             (rules
              (list
               (gerbil-ascent-rule (list (atom 'left '(0))) (list (atom 'seed '(0))))
               (gerbil-ascent-rule (list (atom 'left '(1))) (list (atom 'left '(0))))
               (gerbil-ascent-rule (list (atom 'left '(0))) (list (atom 'left '(1))))
               (gerbil-ascent-rule (list (atom 'right '(0))) (list (atom 'seed '(0))))
               (gerbil-ascent-rule (list (atom 'out '(0)))
                                   (list (atom 'left '(1)) (atom 'right '(0)))))))
        (for-each
         (lambda (relations)
           (let (p (gerbil-ascent-program relations rules 64 64 64))
             (for-each
              (lambda (jobs)
                (let (result (gerbil-ascent-evaluate-program p workers: jobs))
                  (check-equal? (canonical result 'seed) '((0)))
                  (check-equal? (canonical result 'left) '((0) (1)))
                  (check-equal? (canonical result 'right) '((0)))
                  (check-equal? (canonical result 'out) '((0))))) '(1 2 4))))
         (list (list seed left right out) (list seed right left out)))))
    (test-case "all three-relation graphs preserve exact SCC partition edges and head ownership"
      (for-each
       (lambda (bits)
         (let* ((names '(a b c)) (edges []) (reach (make-vector 9 #f)))
           (for-each (lambda (i) (vector-set! reach (+ (* 3 i) i) #t)) (iota 3))
           (for-each
            (lambda (i)
              (when (not (zero? (bitwise-and bits (arithmetic-shift 1 i))))
                (let ((source (quotient i 3)) (target (modulo i 3)))
                  (set! edges (cons (cons source target) edges))
                  (vector-set! reach i #t)))) (iota 9))
           ;; Independent Floyd closure: no production adjacency or Tarjan reuse.
           (for-each
            (lambda (k)
              (for-each (lambda (i)
                          (for-each (lambda (j)
                                      (when (and (vector-ref reach (+ (* 3 i) k))
                                                 (vector-ref reach (+ (* 3 k) j)))
                                        (vector-set! reach (+ (* 3 i) j) #t))) (iota 3))) (iota 3))) (iota 3))
           (let* ((p (gerbil-ascent-program
                      (map (lambda (name) (gerbil-ascent-relation name 0 [])) names)
                      (map (lambda (edge)
                             (gerbil-ascent-rule
                              (list (gerbil-ascent-atom (list-ref names (cdr edge)) []))
                              (list (gerbil-ascent-atom (list-ref names (car edge)) [])))) edges)
                      64 64 64))
                  (analysis (.ref (gerbil-ascent-make-engine p #t) '.analysis))
                  (components (gerbil-ascent-compile-positive-components analysis))
                  (owners (make-vector 3 #f)))
             (for-each
              (lambda (component)
                (for-each (lambda (relation)
                            (check-equal? (vector-ref owners relation) #f)
                            (vector-set! owners relation (positive-component-id component)))
                          (positive-component-members component))
                (for-each
                 (lambda (rule)
                   (for-each (lambda (output)
                               (check-equal? (if (memv (vector-ref (vector-ref output 0) 0)
                                                      (positive-component-members component)) #t #f) #t))
                             (vector-ref (vector-ref rule 0) 0)))
                 (positive-component-rules component))) components)
             (check-equal? (apply + (map (lambda (component)
                                         (apply + (map (lambda (rule) (length (vector-ref (vector-ref rule 0) 0)))
                                                       (positive-component-rules component)))) components))
                           (length edges))
             (for-each
              (lambda (i)
                (check-equal? (number? (vector-ref owners i)) #t)
                (for-each
                 (lambda (j)
                   (check-equal? (= (vector-ref owners i) (vector-ref owners j))
                                 (and (vector-ref reach (+ (* 3 i) j)) (vector-ref reach (+ (* 3 j) i))))) (iota 3))) (iota 3))
             (for-each
              (lambda (target)
                (for-each
                 (lambda (source)
                   (let* ((a (positive-component-id source)) (b (positive-component-id target))
                          (expected (and (not (= a b))
                                         (ormap (lambda (edge) (and (= a (vector-ref owners (car edge)))
                                                                   (= b (vector-ref owners (cdr edge))))) edges)))
                          (actual (if (memv a (positive-component-predecessors target)) #t #f)))
                     (check-equal? actual expected)
                     (when expected (check-equal? (< a b) #t)))) components)) components))
           (when (zero? (modulo (+ bits 1) 16))
             (displayln "COMPONENT-GRAPHS-CHECKED " (+ bits 1) "/512") (force-output))))
       (iota 512)))
    (test-case "actual SCC workers emit exact semantic closure from frozen snapshots"
      ;; This Case owns worker execution. Schema/rules are identical across
      ;; graph inputs; each worker still gets a fresh explicit fact snapshot.
      (let* ((request (component-scope-request (program [])))
             (analysis (vector-ref request 0)) (schema (vector-ref request 1))
             (components (gerbil-ascent-compile-positive-components analysis)))
       (for-each
       (lambda (bits)
         (let ((edges []) (reach (make-vector 9 #f)))
           (for-each (lambda (i)
                       (when (not (zero? (bitwise-and bits (arithmetic-shift 1 i))))
                         (set! edges (cons (list (quotient i 3) (modulo i 3)) edges))
                         (vector-set! reach i #t))) (iota 9))
           (for-each
            (lambda (k)
              (for-each (lambda (i)
                          (for-each (lambda (j)
                                      (when (and (vector-ref reach (+ (* 3 i) k))
                                                 (vector-ref reach (+ (* 3 k) j)))
                                        (vector-set! reach (+ (* 3 i) j) #t))) (iota 3))) (iota 3))) (iota 3))
           (let* ((truth (filter (lambda (edge) (vector-ref reach (+ (* 3 (car edge)) (cadr edge))))
                                 (append-map (lambda (i) (map (lambda (j) (list i j)) (iota 3))) (iota 3))))
                  (frontier (vector-copy (vector-ref request 2)))
                  (expected (vector edges truth edges edges '((7) (8)) '((7) (8))))
                  (emitted (make-hash-table)))
             (vector-set! frontier 0 edges)
             (for-each
              (lambda (component)
                (let* ((before (vector-copy frontier)) (local (vector-copy frontier))
                       (sizes (vector-map length local)))
                  (gerbil-ascent-run-positive-component! component schema
                   (make-component-snapshot local sizes)
                   (lambda (atom row)
                     (let* ((index (vector-ref atom 0)) (key (cons index row)))
                       (check-equal? (if (memv index (positive-component-members component)) #t #f) #t)
                       (check-equal? (if (member row (vector-ref expected index)) #t #f) #t)
                       (check-equal? (hash-get emitted key) #f)
                       (hash-put! emitted key #t)
                       (vector-set! frontier index (cons row (vector-ref frontier index)))))
                   (lambda () (void)))
                  (for-each
                   (lambda (index)
                     (if (memv index (positive-component-members component))
                       (begin
                         (check-equal? (length (vector-ref local index)) (length (vector-ref expected index)))
                         (check-equal? (length (vector-ref frontier index)) (length (vector-ref expected index)))
                         (for-each (lambda (row)
                                     (check-equal? (if (member row (vector-ref local index)) #t #f) #t)
                                     (check-equal? (if (member row (vector-ref frontier index)) #t #f) #t))
                                   (vector-ref expected index)))
                       (check-equal? (eq? (vector-ref local index) (vector-ref before index)) #t))) (iota 6))
                  ;; A completed private snapshot must already be closed under
                  ;; a fresh full initialization, not merely have stopped its
                  ;; delta loop. Seeded output membership suppresses old rows.
                  (let (closed (vector-copy local))
                    (gerbil-ascent-run-positive-component! component schema
                     (make-component-snapshot local (vector-map length local))
                     (lambda (atom row) (error "completed SCC emitted a missing consequence" atom row))
                     (lambda () (void)))
                    (for-each (lambda (index)
                                (check-equal? (eq? (vector-ref local index) (vector-ref closed index)) #t))
                              (iota 6)))))
              components)
             (for-each (lambda (index)
                         (check-equal? (length (vector-ref frontier index)) (length (vector-ref expected index)))) (iota 6)))
           (when (zero? (modulo (+ bits 1) 16))
             (displayln "WORKER-TRACES-CHECKED " (+ bits 1) "/512") (force-output))))
       (iota 512))))
    (test-case "merge failure and credited cancellation drain without completion"
      (for-each
       (lambda (mode)
         (let ((terminated? #f) (merged 0) (completed 0))
           (check-equal?
            (rejected?
             (lambda ()
               (gerbil-ascent-run-actor-round! (vector mode) '(producer) 2
                (lambda (_ emit! checkpoint!)
                  (try (for-each (lambda (n) (emit! 'out (list n))) (iota 65))
                       (finally (set! terminated? #t))))
                (lambda (_ row)
                  (set! merged (+ merged 1))
                  (when (eq? mode 'merge-failure) (error "planned merge failure")))
                (lambda () (and (eq? mode 'cancel) (>= merged 32)))
                (lambda (_) #t)
                (lambda (_) (set! completed (+ completed 1)))))) #t)
           (check-equal? terminated? #t)
           (check-equal? completed 0)
           (check-equal? merged (if (eq? mode 'cancel) 32 1))))
       '(merge-failure cancel)))
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
