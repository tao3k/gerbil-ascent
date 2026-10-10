;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil-ascent/program/actor-round gerbil-ascent-run-actor-round!)
        :gerbil-ascent/t/performance/actor-credit/fixture
        (only-in :gerbil-ascent/t/performance/component-index/fixture component-index-normalize))
(import (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-actor-credit-performance-test)
(def (require-native!)
  (unless (getenv "ASCENT_TEST_LIBRARY" #f)
    (error "matched performance samples require compiled native qualification"))
  (assert-native-library!))
(def (sample call)
  (let* ((before (##process-statistics)) (start (current-jiffy)) (result (call))
         (elapsed (- (current-jiffy) start)) (after (##process-statistics)))
    (vector result
            (* 1000000 (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                          (+ (f64vector-ref before 0) (f64vector-ref before 1))))
            (* 1000000 (/ elapsed (jiffies-per-second))))))
(def ascent-actor-credit-performance-test
  (test-suite "Compiled ascent-actor-credit matched measurements"
    (test-case "matched stream and recursive actor costs check every sample"
      (require-native!)
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
