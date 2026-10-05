;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil-ascent/program/actor-round gerbil-ascent-run-actor-round!)
        :gerbil-ascent/t/performance/actor-credit/fixture
        (only-in :gerbil-ascent/t/performance/component-index/fixture component-index-normalize))
(export ascent-actor-credit-test)
(def (rejected? thunk) (with-catch (lambda (_) #t) (lambda () (thunk) #f)))
(def (sample call)
  (let* ((before (##process-statistics)) (start (current-jiffy)) (result (call))
         (elapsed (- (current-jiffy) start)) (after (##process-statistics)))
    (vector result
            (* 1000000 (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                          (+ (f64vector-ref before 0) (f64vector-ref before 1))))
            (* 1000000 (/ elapsed (jiffies-per-second))))))
(def ascent-actor-credit-test
  (test-suite "Successful credit restarts the checkpoint window"
    (test-case "dense stream has exact candidates and no redundant owner checks"
      (let ((old (credit-stream #t 256)) (new (credit-stream #f 256)))
        (check-equal? (credit-stream-truth old 256) #t)
        (check-equal? (credit-stream-truth new 256) #t)
        ;; Initial owner check + two checks per request + two terminal loops.
        (check-equal? (vector-ref old 1) (+ 1 (* 2 (+ 16 8)) 2))
        (check-equal? (vector-ref new 1) (+ 1 (* 2 16) 2))))
    (test-case "dense cancellation refuses later candidates and drains both workers"
      (let ((checks 0) (merged 0) (terminated 0) (lock (make-mutex)))
        (check-equal? (rejected? (lambda ()
          (gerbil-ascent-run-actor-round! (vector 'cancel-dense) '(a b c) 2
           (lambda (task emit! checkpoint!)
             (try (for-each (lambda (k) (checkpoint!) (emit! task (list k))) (iota 10000))
                  (finally (mutex-lock! lock) (set! terminated (+ terminated 1)) (mutex-unlock! lock))))
           (lambda (_ row) (set! merged (+ merged 1)))
           (lambda () (set! checks (+ checks 1)) (> checks 4))))) #t)
        (check-equal? merged 64)
        (check-equal? terminated 2)))
    (test-case "matched stream and recursive actor costs check every sample"
      (let ((request (credit-request)) (truth (credit-truth)))
        (for-each
         (lambda (mode)
           (for-each
            (lambda (pair)
              (let* ((call (lambda (old?) (if (eq? mode 'stream) (credit-stream old? 4096) (credit-closure old? request))))
                     (old-first? (even? pair)) (a (sample (lambda () (call old-first?))))
                     (b (sample (lambda () (call (not old-first?)))))
                     (old (if old-first? a b)) (new (if old-first? b a)))
                (for-each (lambda (result)
                            (if (eq? mode 'stream)
                              (check-equal? (credit-stream-truth result 4096) #t)
                              (check-equal? (component-index-normalize result) truth)))
                          (list (vector-ref old 0) (vector-ref new 0)))
                (displayln "ACTOR-CREDIT-TIME mode=" mode " pair=" pair
                           " old-cpu-us=" (vector-ref old 1) " new-cpu-us=" (vector-ref new 1)
                           " old-wall-us=" (vector-ref old 2) " new-wall-us=" (vector-ref new 2))
                (force-output))) (iota 50))) '(stream closure))))))
