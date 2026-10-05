;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil/runtime/gambit call-with-output-string display-exception)
        (only-in :gerbil-ascent/program/source-cut
                 gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows
                 gerbil-ascent-source-cut-update)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        :gerbil-ascent/program/objects
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
    (test-case "source budget refusal precedes row copying and preserves validation order"
      (let* ((positions (make-hash-table-eq)) (arities '#(2 1)))
        (hash-put! positions 'edge 1) (hash-put! positions 'other 2)
        (let* ((cut (gerbil-ascent-make-source-cut positions arities
                     '((edge (0 1)) (other (7)))))
               (small (list (cons 'edge (make-list 10000 '(2 3)))))
               (large (list (cons 'edge (make-list 20000 '(2 3)))))
               (counter (make-f64vector 2 0.0)))
          (def (refusal-bytes batch append?)
            (##gc)
            (##get-bytes-allocated! counter 0)
            (let (failure
                  (diagnostic (lambda ()
                    (gerbil-ascent-source-cut-update cut positions arities batch append? 2))))
              (##get-bytes-allocated! counter 1)
              (check-equal? (if (string-contains failure "input fact budget exceeded") #t #f) #t)
              (check-equal? (gerbil-ascent-source-cut-rows cut 0) '((0 1)))
              (check-equal? (gerbil-ascent-source-cut-rows cut 1) '((7)))
              (- (f64vector-ref counter 1) (f64vector-ref counter 0))))
          ;; Warm exception formatting before comparing native allocation.
          (refusal-bytes small #f)
          (for-each
           (lambda (append?)
             (let ((a (refusal-bytes small append?)) (b (refusal-bytes large append?)))
               ;; A doubled rejected row batch must not allocate row spines.
               ;; This fixture allows formatting noise, not per-row copies.
               (check-equal? (< b (+ a 4096)) #t)
               (displayln "SOURCE-CUT-REFUSAL append=" append? " small-bytes=" a " large-bytes=" b)
               (force-output))) '(#f #t))
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
    (test-case "failed computation cannot publish tentative candidates"
      (let (session (gerbil-ascent-open-actor-session (program '((0 1)) 2)))
        (try
         (let (first (gerbil-ascent-session-run session))
           (gerbil-ascent-session-append-source! session 'edge '(1 2))
           (check-equal? (outcome (lambda () (gerbil-ascent-session-run session))) 'rejected)
           (check-equal? (eq? first (gerbil-ascent-session-last-completed session)) #t)
           (check-equal? (rows (gerbil-ascent-session-run session)) '((0 1))))
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
