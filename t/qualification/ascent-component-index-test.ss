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
))
