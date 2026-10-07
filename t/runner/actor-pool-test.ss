;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in "actor-pool.ss" run-actor-pool!)
        (only-in "module-process.ss" make-native-receipt native-receipt-line!
                 native-receipt-ok? run-test-child))
(export actor-pool-test)

(def actor-pool-test
  (test-suite "Native actor test coordinator"
    (test-case "native receipt rejects missing verdicts, empty modules and swallowed errors"
      (let* ((path "t/runner/native-registry-test.ss")
             (module (path-expand "gerbil-ascent/t/runner/native-registry-test.ssi"
                                  (getenv "ASCENT_TEST_LIBRARY")))
             (lines (list "NATIVE-MODULES-OK" (string-append "MODULE " module)
                          "CASE control" (string-append "MODULE-OK " module)
                          (string-append "HARNESS-OK " path) "OK")))
        (def (admitted? trace status)
          (let (receipt (make-native-receipt path))
            (for-each (lambda (line) (native-receipt-line! receipt line)) trace)
            (native-receipt-ok? receipt status)))
        (check-equal? (admitted? lines 0) #t)
        (for-each (lambda (marker)
                    (check-equal? (admitted? (filter (lambda (line) (not (equal? line marker))) lines) 0) #f))
                  (list "NATIVE-MODULES-OK" "CASE control"
                        (string-append "MODULE-OK " module)
                        (string-append "HARNESS-OK " path) "OK"))
        (for-each (lambda (error-line)
                    (check-equal? (admitted? (append lines (list error-line)) 0) #f))
                  '("ERROR CASE injected" "ERROR CHECK injected" "ERROR MODULE injected"
                    "ERROR HARNESS injected" "*** Heap overflow" "*** Stack overflow"
                    "MODULE-OK other-module"))
        (check-equal? (admitted? lines 42) #f)))
    (test-case "direct child preserves setup, Case, cleanup and empty Suite failures"
      (let ((path "t/runner/native-registry-test.ss")
            (previous (getenv "ASCENT_NATIVE_ENTRY_CONTROL" "")))
        (try
          (for-each
           (lambda (control)
             (setenv "ASCENT_NATIVE_ENTRY_CONTROL" (car control))
             ;; Nested negative transcripts belong to the control's receipt,
             ;; not the enclosing successful Suite's admission stream.
             (check-equal? (run-test-child path void) (cdr control))
             (displayln "NATIVE-CHILD-CONTROL-OK " (car control) " exit=" (cdr control))
             (force-output))
           '(("" . 0) ("setup" . 42) ("case" . 42) ("cleanup" . 42) ("empty" . 70)))
          (finally (setenv "ASCENT_NATIVE_ENTRY_CONTROL" previous)))))
    (test-case "two assigned tasks overlap without a wall clock assumption"
      (let* ((observed [])
             (barrier (spawn/name 'qualification-barrier
                        (lambda ()
                          (let ((left (thread-receive)) (right (thread-receive)))
                            (thread-send left 'release) (thread-send right 'release)))))
             (result
              (run-actor-pool! '(left right later) 2
                (lambda (task emit)
                  (when (memq task '(left right))
                    (thread-send barrier (current-thread))
                    (check-equal? (thread-receive 1 'timeout) 'release))
                  (emit task) 0)
                (lambda (line) (set! observed (cons line observed))))))
        (thread-join! barrier 1)
        (check-equal? result 0)
        (check-equal? (length observed) 3)
        (for-each (lambda (task) (check-equal? (and (memq task observed) #t) #t)) '(left right later))))
    (test-case "observed failure stops further admission"
      (let (ran [])
        (check-equal? (run-actor-pool! '(fail forbidden) 1
                        (lambda (task emit) (emit task) 42)
                        (lambda (line) (set! ran (cons line ran)))) 42)
        (check-equal? ran '(fail))))
    (test-case "output sink failure drains assigned workers"
      (let ((completed (vector #f #f))
            (barrier (spawn (lambda ()
                             (let ((a (thread-receive)) (b (thread-receive)))
                               (thread-send a 'release) (thread-send b 'release))))))
        (check-equal? (run-actor-pool! '(a b forbidden) 2
                        (lambda (task emit)
                          (thread-send barrier (current-thread))
                          (check-equal? (thread-receive 1 'timeout) 'release)
                          (emit task)
                          (vector-set! completed (if (eq? task 'a) 0 1) #t) 0)
                        (lambda (line) (error "injected output sink failure"))) 70)
        (thread-join! barrier 1)
        (check-equal? completed (vector #t #t))))
    (test-case "caller mailbox is isolated from coordinator messages"
      (thread-send (current-thread) 'unrelated)
      (check-equal? (run-actor-pool! '(a) 1 (lambda (task emit) 0)) 0)
      (check-equal? (thread-receive 1 'timeout) 'unrelated))
    (test-case "uncaught worker exception is monitored and returned as failure"
      (check-equal? (run-actor-pool! '(bad forbidden) 1
                      (lambda (task emit) (error "injected worker exit")) void) 70))
    (test-case "serial credits preserve order and empty pool completes"
      (let (seen [])
        (check-equal? (run-actor-pool! '(a b c) 1
                        (lambda (task emit) (emit task) (emit task) 0)
                        (lambda (line) (set! seen (cons line seen)))) 0)
        (check-equal? (reverse seen) '(a a b b c c))
        (check-equal? (run-actor-pool! [] 2 (lambda args (error "empty pool assigned task"))) 0)))))
