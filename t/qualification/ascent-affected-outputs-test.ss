;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :gerbil-ascent/core/positive-plan
        :gerbil-ascent/program/update-selection
        (prefix-in :gerbil-ascent/t/performance/affected-outputs/reference old-))
(export ascent-affected-outputs-test)

(def (output-rule)
  (let* ((heads (map (lambda (n) (vector n '((variable . x)))) '(2 0 2 1)))
         (body (list (vector 'atom (vector 3 '((variable . x)) []))))
         (plan (gerbil-ascent-compile-positive-plan heads body)))
    (vector heads body 0 0 '#() plan (vector 'untouched))))
(def (selected-rule select rule affected)
  (car (vector-ref (select (vector (list rule)) affected) 0)))
(def (head-ids rule) (map (lambda (head) (vector-ref head 0)) (vector-ref rule 0)))
(def (output-ids rule)
  (map (lambda (output) (vector-ref (vector-ref output 0) 0))
       (vector-ref (vector-ref rule 5) 0)))

(def ascent-affected-outputs-test
  (test-suite "Affected output ownership"
    (test-case "all masks retain ordered duplicate heads and outputs"
      (for-each
       (lambda (bits)
         (let* ((rule (output-rule))
                (affected (list->vector
                           (map (lambda (n) (odd? (quotient bits (expt 2 n)))) (iota 4))))
                (expected (filter (lambda (n) (vector-ref affected n)) '(2 0 2 1)))
                (new (vector-ref (gerbil-ascent-select-rule-plans (vector (list rule)) affected) 0))
                (old (vector-ref (old-gerbil-ascent-select-rule-plans (vector (list rule)) affected) 0)))
           (check-equal? (map head-ids new) (map head-ids old))
           (check-equal? (map output-ids new) (map output-ids old))
           (check-equal? (map head-ids new) (if (null? expected) [] (list expected)))
           (check-equal? (map output-ids new) (if (null? expected) [] (list expected)))))
       (iota 16)))
    (test-case "full survivors retain rule plan head spine and frame identity"
      (let* ((rule (output-rule))
             (selected (selected-rule gerbil-ascent-update-active-plans rule '#(#t #t #t #f))))
        (check-equal? (eq? selected rule) #t)
        (check-equal? (eq? (vector-ref selected 0) (vector-ref rule 0)) #t)
        (check-equal? (eq? (vector-ref selected 5) (vector-ref rule 5)) #t)
        (check-equal? (eq? (vector-ref selected 6) (vector-ref rule 6)) #t)
        (check-equal? (vector-ref (vector-ref rule 6) 0) 'untouched)))
    (test-case "partial spines are detached after first middle and last rejection"
      (for-each
       (lambda (mask)
         (let* ((rule (output-rule))
                (projected (selected-rule gerbil-ascent-select-rule-plans rule mask))
                (heads (vector-ref projected 0))
                (outputs (vector-ref (vector-ref projected 5) 0)))
           ;; Mutate each retained pair, including the last; no caller tail may alias.
           (for-each (lambda (pair) (set-cdr! pair []))
                     (let collect ((rest heads)) (if (null? rest) [] (cons rest (collect (cdr rest))))))
           (for-each (lambda (pair) (set-cdr! pair []))
                     (let collect ((rest outputs)) (if (null? rest) [] (cons rest (collect (cdr rest))))))
           (check-equal? (head-ids rule) '(2 0 2 1))
           (check-equal? (output-ids rule) '(2 0 2 1))))
       (list '#(#t #t #f #f) '#(#f #t #t #f) '#(#t #f #t #f))))
    (test-case "partial activations share lowered actions but own new frames"
      (let* ((rule (output-rule)) (mask '#(#t #f #t #f))
             (a (selected-rule gerbil-ascent-update-active-plans rule mask))
             (b (selected-rule gerbil-ascent-update-active-plans rule mask)))
        (check-equal? (vector-length a) 7)
        (check-equal? (eq? (vector-ref a 1) (vector-ref rule 1)) #t)
        (check-equal? (eq? (vector-ref (vector-ref a 5) 1) (vector-ref (vector-ref rule 5) 1)) #t)
        (check-equal? (eq? (vector-ref a 6) (vector-ref rule 6)) #f)
        (check-equal? (eq? (vector-ref a 6) (vector-ref b 6)) #f)
        (vector-set! (vector-ref a 6) 0 'private)
        (check-equal? (vector-ref (vector-ref b 6) 0) #f)))
    (test-case "absent compiled plans retain selected-head lowering"
      (let (rule (output-rule))
        (vector-set! rule 5 #f)
        (let ((a (selected-rule gerbil-ascent-select-rule-plans rule '#(#t #f #t #f)))
              (b (selected-rule old-gerbil-ascent-select-rule-plans rule '#(#t #f #t #f))))
          (check-equal? (head-ids a) (head-ids b))
          (check-equal? (output-ids a) (output-ids b)))))
    (test-case "empty and fully excluded strata retain shape"
      (check-equal? (gerbil-ascent-update-active-plans '#() '#()) '#())
      (check-equal? (gerbil-ascent-update-active-plans (vector [] (list (output-rule))) '#(#f #f #f #f))
                    (vector [] [])))))
