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
(export ascent-component-index-test)
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
(def ascent-component-index-test
  (test-suite "SCC incremental total-index maintenance"
    (test-case "extension preserves rebuild bucket order and old source roots"
      (let* ((rows (map (lambda (n) (list 0 n)) (iota 32)))
             (before (map (lambda (row) (map values row)) rows))
             (h (index-entry-harness #f rows gerbil-ascent-hash-index-provider))
             (query (vector-ref h 0)) (advance! (vector-ref h 1))
             (atom (index-entry-atom '(0) '(0))) (batch '((0 35) (0 34) (0 33))))
        (check-equal? (query atom [] #f #f) rows)
        (advance! 0 batch #t)
        (vector-set! (vector-ref h 2) 0 (append batch rows))
        (vector-set! (vector-ref h 4) 0 35)
        (vector-set! (vector-ref h 6) 0 1)
        (check-equal? (query atom [] #f #f)
                      (gerbil-ascent-physical-index-single-rows
                       (gerbil-ascent-physical-index-build gerbil-ascent-hash-index-provider (append batch rows) '(0)) 0))
        (check-equal? rows before)))
    (test-case "single and composite-key workers match independent closure truth"
      (for-each
       (lambda (case)
         (let* ((n (car case)) (tagged? (cadr case)) (cycle? (caddr case))
                (p (component-index-program n tagged? cycle?))
                (request (component-index-request p)) (initial (vector-copy (vector-ref request 2)))
                (truth (component-index-truth n tagged? cycle?)))
           (for-each (lambda (old?)
                       (check-equal? (component-index-normalize (component-index-run old? request)) truth)
                       (check-equal? (vector-ref request 2) initial)) '(#t #f))
           (for-each (lambda (jobs)
                       (check-equal? (component-index-normalize ((.ref (gerbil-ascent-evaluate-program p workers: jobs) 'rows-of) 'path)) truth)) '(1 2 4))))
       '((1 #f #f) (16 #t #f) (64 #f #f) (64 #t #f) (16 #t #t))))
    (test-case "matched recursive index cost retains truth in every pair"
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
