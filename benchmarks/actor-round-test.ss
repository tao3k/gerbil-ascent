;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        :gerbil/runtime/gambit
        (only-in :gerbil-ascent/program/actor-round gerbil-ascent-run-actor-round!))
(export actor-round-test actor-batch-spine-test)

(def (display-round name entries)
  (display "ACTOR-ROUND ")
  (write (cons (cons 'phase name) entries))
  (newline))

(def (measure-round name tasks jobs checks rows)
  (check-equal? (##current-vm-processor-count) 1)
  (let* ((key (vector name))
         (assignments (iota tasks))
         (received (make-vector tasks 0))
         (completed (make-vector tasks #f))
         (finished 0)
         (checkpoint-polls 0))
    (def (execute task emit! checkpoint!)
      (let work ((index 0))
        (unless (= index checks)
          (checkpoint!)
          (work (+ index 1))))
      (let emit ((index 0))
        (unless (= index rows)
          (emit! task index)
          (emit (+ index 1)))))
    (def (merge task row)
      (let (expected (vector-ref received task))
        (unless (= expected row)
          (error "Actor round changed task row order" task expected row))
        (vector-set! received task (+ expected 1))))
    (def (complete task)
      (unless (and (= (vector-ref received task) rows)
                   (not (vector-ref completed task)))
        (error "Actor round published an incomplete or repeated task" task))
      (vector-set! completed task #t)
      (set! finished (+ finished 1)))
    (##gc)
    (let* ((counter (make-f64vector 2 0.))
           (before (##process-statistics))
           (start (current-jiffy)))
      (##get-bytes-allocated! counter 0)
      (gerbil-ascent-run-actor-round! key assignments jobs execute merge
        (lambda () (set! checkpoint-polls (+ checkpoint-polls 1)) #f)
        (lambda (_) #t) complete)
      (##get-bytes-allocated! counter 1)
      (let* ((end (current-jiffy))
             (after (##process-statistics)))
        (##gc)
        (let* ((collected (##process-statistics))
               (bytes (- (f64vector-ref collected 16) (f64vector-ref before 16))))
          (check-equal? finished tasks)
          (display-round name
            (list (cons 'tasks tasks) (cons 'workers jobs)
                  (cons 'checkpoints-per-task checks) (cons 'rows-per-task rows)
                  (cons 'coordinator-cancel-polls checkpoint-polls)
                  (cons 'elapsed-us (/ (* 1000000 (- end start)) (jiffies-per-second)))
                  (cons 'cpu-us
                    (* 1000000. (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                                   (+ (f64vector-ref before 0) (f64vector-ref before 1)))))
                  (cons 'collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
                  (cons 'batch-messages (* tasks (quotient rows 32)))
                  (cons 'checkpoint-messages (* tasks (quotient checks 64)))
                  (cons 'collected-allocation-delta bytes)
                  (cons 'direct-allocation-delta
                    (- (f64vector-ref counter 1) (f64vector-ref counter 0)))
                  (cons 'valid-collected-allocation? (>= bytes 0))
                  (cons 'last-gc-live-bytes (f64vector-ref collected 17)))))))))

(def (measure-cancel)
  (let ((begun 0) (unwound 0) (merged 0) (requested #f) (resumed? #f))
    (def (execute task emit! checkpoint!)
      (set! begun (+ begun 1))
      (dynamic-wind
        void
        (lambda ()
          (let emit ((next 0))
            (unless (= next 64)
              (emit! task next)
              (when (= next 32) (set! resumed? #t))
              (emit (+ next 1)))))
        (lambda () (set! unwound (+ unwound 1)))))
    (def (merge task row)
      (unless (and (= task 0) (= row merged))
        (error "Actor cancellation changed the admitted batch" task row))
      (unless requested (set! requested (current-jiffy)))
      (set! merged (+ merged 1)))
    (check-exception
     (gerbil-ascent-run-actor-round! (vector 'cancel) '(0 1) 1 execute merge
       (lambda () (not (not requested))))
     (lambda (failure) (equal? (error-message failure) "ASCENT actor round canceled")))
    (let (end (current-jiffy))
      (check-equal? begun 1)
      (check-equal? unwound 1)
      (check-equal? merged 32)
      (check-equal? resumed? #t)
      (display-round 'cancel-drain
        (list (cons 'begun begun) (cons 'cleaned-up unwound)
              (cons 'merged-before-refusal merged)
              (cons 'worker-received-credit? resumed?)
              (cons 'cancel-to-drain-us (/ (* 1000000 (- end requested)) (jiffies-per-second))))))))

(def actor-round-test
  (test-suite "Single VM Actor round phases"
    (test-case "dispatch, checkpoint credits and row publication"
      (measure-round 'dispatch 4096 1 0 0)
      (measure-round 'checkpoint 4096 1 64 0)
      (measure-round 'batch-and-tail 4096 1 0 33)
      (measure-round 'batch-and-tail 4096 4 0 33))
    (test-case "canceled round drains the assigned worker and retires pending tasks"
      (measure-cancel))))


;;; Isolate the native reversal from mailbox stack switches in actor-round-test.
;;; Both arms prepare the same private spines before starting the counter.
(def (measure-batch-spine transfer!)
  (let* ((repeats 4096)
         (batches (map (lambda (_) (reverse (iota 32))) (iota repeats)))
         (tail (map (lambda (_) (list 32)) (iota repeats)))
         (counter (make-f64vector 2 0.)))
    (##gc)
    (let (before (##process-statistics))
      (##get-bytes-allocated! counter 0)
      (let ((returned (map transfer! batches))
            (returned-tail (map transfer! tail)))
        (##get-bytes-allocated! counter 1)
        (##gc)
        (let* ((after (##process-statistics))
               (collected (- (f64vector-ref after 16) (f64vector-ref before 16)))
               (direct (- (f64vector-ref counter 1) (f64vector-ref counter 0)))
               (expected (iota 32)))
          (check-equal? (andmap (cut equal? <> expected) returned) #t)
          (check-equal? (andmap (cut equal? <> '(32)) returned-tail) #t)
          (display-round 'batch-spine
            (list (cons 'transfer? (eq? transfer! reverse!))
                  (cons 'rows (* repeats 33))
                  (cons 'direct-allocation-delta direct)
                  (cons 'collected-allocation-delta collected)
                  (cons 'valid-collected-allocation? (>= collected 0)))))))))

(def actor-batch-spine-test
  (test-suite "Owned batch spine reversal"
    (test-case "copy and transfer produce identical full batches and tails"
      (measure-batch-spine reverse)
      (measure-batch-spine reverse!))))
