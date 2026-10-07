;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :std/test check-equal? test-case test-suite)
        :gerbil-ascent/t/performance/component-index/fixture
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/performance/index-entry/fixture index-entry-harness index-entry-atom)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/access gerbil-ascent-physical-index-build gerbil-ascent-physical-index-single-rows))
(import (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-component-index-performance-test)
(def (require-native!)
  (unless (getenv "ASCENT_TEST_LIBRARY" #f)
    (error "matched performance samples require compiled native qualification"))
  (assert-native-library!))
(def (sample request old? (run component-index-run))
  (let* ((before (##process-statistics)) (start (current-jiffy))
         (result (run old? request)) (elapsed (- (current-jiffy) start))
         (after (##process-statistics)))
    (vector result
            (* 1000000 (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                          (+ (f64vector-ref before 0) (f64vector-ref before 1))))
            (* 1000000 (/ elapsed (jiffies-per-second))))))
(def (allocation request old?)
  (##gc)
  (let* ((before (f64vector-ref (##process-statistics) 16))
         (result (component-index-run old? request)))
    (##gc)
    (let (bytes (- (f64vector-ref (##process-statistics) 16) before))
      (when (< bytes 0) (error "nonmonotonic allocation counter"))
      (vector result bytes))))
(def ascent-component-index-performance-test
  (test-suite "Compiled ascent-component-index matched measurements"
    (test-case "matched recursive index cost retains truth in every pair"
      (require-native!)
      (for-each
       (lambda (tagged?)
         (let* ((n 64) (request (component-index-request (component-index-program n tagged? #f)))
                (truth (component-index-truth n tagged? #f)))
           (def (validate result) (check-equal? (component-index-normalize result) truth))
           (validate (component-index-run #t request)) (validate (component-index-run #f request))
           (for-each
            (lambda (pair)
              (let* ((old-first? (even? pair))
                     (a (sample request old-first?)) (b (sample request (not old-first?)))
                     (old (if old-first? a b)) (new (if old-first? b a)))
                (validate (vector-ref old 0)) (validate (vector-ref new 0))
                (displayln "COMPONENT-INDEX-TIME tagged=" tagged? " pair=" pair
                           " old-cpu-us=" (vector-ref old 1) " new-cpu-us=" (vector-ref new 1)
                           " old-wall-us=" (vector-ref old 2) " new-wall-us=" (vector-ref new 2))
                (force-output))) (iota 50))
           (for-each
            (lambda (pair)
              (let* ((old-first? (even? pair))
                     (a (allocation request old-first?)) (b (allocation request (not old-first?)))
                     (old (if old-first? a b)) (new (if old-first? b a)))
                (validate (vector-ref old 0)) (validate (vector-ref new 0))
                (displayln "COMPONENT-INDEX-ALLOCATION tagged=" tagged? " pair=" pair
                           " old-bytes=" (vector-ref old 1) " new-bytes=" (vector-ref new 1))
                (force-output))) (iota 10)))) '(#f #t)))
    (test-case "real actor coordinator cost retains independent truth"
      (require-native!)
      (let* ((n 64) (request (component-index-request (component-index-program n #t #f)))
             (truth (component-index-truth n #t #f)))
        (for-each
         (lambda (pair)
           (let* ((old-first? (even? pair))
                  (a (sample request old-first? component-index-run-coordinator))
                  (b (sample request (not old-first?) component-index-run-coordinator))
                  (old (if old-first? a b)) (new (if old-first? b a)))
             (check-equal? (component-index-normalize (vector-ref old 0)) truth)
             (check-equal? (component-index-normalize (vector-ref new 0)) truth)
             (displayln "COMPONENT-INDEX-ACTOR pair=" pair
                        " old-cpu-us=" (vector-ref old 1) " new-cpu-us=" (vector-ref new 1)
                        " old-wall-us=" (vector-ref old 2) " new-wall-us=" (vector-ref new 2))
             (force-output))) (iota 20))))))
