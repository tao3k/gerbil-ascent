;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        :gerbil-ascent/t/performance/selected-activation/fixture
        (only-in :gerbil-ascent/program/update-selection gerbil-ascent-select-rule-plans))
(export ascent-selected-activation-test)
(def ascent-selected-activation-test
  (test-suite "Selective engine-owned rule activation"
    (test-case "every mask preserves ordered duplicate outputs and generic fallback"
      (for-each
       (lambda (positive?)
         (for-each
          (lambda (bits)
            (let* ((analysis (activation-metadata 3 8 #t positive?))
                   (affected (list->vector (map (lambda (n) (odd? (quotient bits (expt 2 n)))) (iota 6))))
                   (pure (gerbil-ascent-select-rule-plans (vector-ref analysis 5) affected))
                   (old (activation-selected #t analysis affected))
                   (new (activation-selected #f analysis affected)))
              (check-equal? (activation-summary new) (activation-summary old))
              ;; Projection retains both the purity flag and compiled atom extent.
              ;; This metadata fixture has an empty body, hence extent zero.
              (for-each
               (lambda (rule)
                 (let (plan (vector-ref rule 5))
                   (when plan
                     (check-equal? (vector-length plan) 5)
                     (check-equal? (vector-ref plan 3) #t)
                     (check-equal? (vector-ref plan 4) 0))))
               (vector-ref new 0))
              (for-each (lambda (rule) (check-equal? (vector-length rule) 6)) (vector-ref pure 0))
              (check-equal? (map (lambda (rule) (vector-length rule)) (vector-ref (vector-ref analysis 5) 0)) '(6 6 6))))
          (iota 64))) '(#t #f)))
    (test-case "selected frames never alias cached metadata or another engine"
      (let* ((analysis (activation-metadata 4 64)) (mask '#(#t #f #f #f))
             (a (car (vector-ref (activation-selected #f analysis mask) 0)))
             (b (car (vector-ref (activation-selected #f analysis mask) 0))))
        (check-equal? (eq? (vector-ref a 5) (vector-ref b 5)) #t)
        (check-equal? (eq? (vector-ref a 6) (vector-ref b 6)) #f)
        (vector-set! (vector-ref a 6) 0 'private)
        (check-equal? (vector-ref (vector-ref b 6) 0) #f)))
    (test-case "complete updates and later appends reactivate unaffected components"
      (for-each
       (lambda (width)
         (let (request (activation-request 16 width))
           (for-each
            (lambda (lifecycle?)
              (let (expected (list 1 (if lifecycle? 16 1) (if lifecycle? 'stratified-semi-naive 'stratified-dependency-invalidation)
                                  (append (list '((0))) (if lifecycle? (list '((0))) [])
                                          (make-list (if lifecycle? 14 15) []))))
                (check-equal? (activation-run #t request lifecycle?) expected)
                (check-equal? (activation-run #f request lifecycle?) expected))) '(#f #t)))) '(1 8 64)))
    (test-case "zero deadline resumes selected work before later full activation"
      (let (request (activation-request 16 8))
        (check-equal? (activation-run #f request #t #t) (activation-run #t request #t #t))))))
