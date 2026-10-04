;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/datum
                 reasoning-bounded-data? candidate-copy-pairs)
        (only-in :gerbil-ascent/candidate/program candidate-language-description)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt reasoning-receipt-status
                 reasoning-receipt-diagnostics reasoning-diagnostic-code
                 reasoning-diagnostic-path))
(export ascent-candidate-description-test)

(def source (reasoning-source-snapshot 'description 0 '((input 1 ((4))))))
(def (attempt clause)
  (reasoning-attempt source
    (list 'candidate '(relation result 1)
          (list 'rule '(result ?out) '(input ?x) clause)
          '(query result ?out) '(limits 16 64 128)) 100000))
(def (diagnostic clause code (path '(clause 2 body 2)))
  (let* ((receipt (attempt clause))
         (problem (car (reasoning-receipt-diagnostics receipt))))
    (check-equal? (reasoning-receipt-status receipt) 'rejected)
    (check-equal? (reasoning-diagnostic-code problem) code)
    (check-equal? (reasoning-diagnostic-path problem) path)))

(def ascent-candidate-description-test
  (test-suite "parser-owned candidate description"
    (test-case "inert publication detaches nested and shared pairs"
      (let* ((shared (cons #f 7))
             (datum (cons shared (cons shared 'tail)))
             (copy (candidate-copy-pairs datum)))
        (check-equal? (reasoning-bounded-data? datum 16 8) #t)
        (check-equal? copy '((#f . 7) (#f . 7) . tail))
        (set-car! shared 'caller-change)
        (check-equal? copy '((#f . 7) (#f . 7) . tail))
        (set-cdr! (car copy) 'published-change)
        (check-equal? (cadr copy) '(#f . 7))
        (check-equal? shared '(caller-change . 7))))
    (test-case "every advertised compute name and arity executes"
      (let* ((description (candidate-language-description))
             (operators (cdr (assq 'operators (cddr description)))))
        (for-each
         (lambda (spec)
           (let* ((name (car spec)) (arity (cadr spec))
                  (inputs (make-list arity '?x)))
             (check-equal? (reasoning-receipt-status
                            (attempt (list 'compute '?out (cons name inputs)))) 'complete)
             (diagnostic (list 'compute '?out (cons name (cons '?x inputs)))
                         'unsupported-operator)))
         (cdr (assq 'compute operators)))))
    (test-case "where forms bind no outputs and reject flat shape"
      (for-each
       (lambda (form)
         (let (receipt
               (reasoning-attempt source
                 (list 'candidate '(relation result 1)
                       (list 'rule '(result ?x) '(input ?x) (list 'where form))
                       '(query result ?x) '(limits 16 64 128)) 100000))
           (check-equal? (reasoning-receipt-status receipt) 'complete)))
       (map (lambda (spec) (cons (car spec) (make-list (cadr spec) '?x)))
            (cdr (assq 'where
                       (cdr (assq 'operators (cddr (candidate-language-description))))))))
      (diagnostic '(where even? ?x) 'invalid-filter)
      (diagnostic '(compute ?out + ?x ?x) 'invalid-computation)
      (diagnostic '(compute ?out (* ?x 2)) 'unsupported-operator)
      (diagnostic '(compute ?out (+ ?missing ?x)) 'unbound-operator-input '(clause 2 body 2 input 1)))
    (test-case "advertised reduction names and arities admit and wrong arity rejects"
      (let (reducers (cdr (assq 'reducers (cddr (candidate-language-description)))))
        (for-each
         (lambda (spec)
           (let ((name (car spec)) (inputs (make-list (cadr spec) '?value)))
             (check-equal? (reasoning-receipt-status
                            (attempt (list 'reduce '?out (cons name inputs) '(input ?value)))) 'complete)
             (diagnostic (list 'reduce '?out (cons name (cons '?value inputs)) '(input ?value))
                         'unsupported-reduction)))
         reducers)))
    (test-case "public description is detached from parser state"
      (let* ((description (candidate-language-description))
             (operators (assq 'operators (cddr description))))
        (set-car! (cadr (cadr operators)) 'changed)
        (check-equal? (cadr (cadr (assq 'operators (cddr (candidate-language-description)))))
                      '(even? 1))
        (check-equal? (reasoning-receipt-status (attempt '(compute ?out (+ ?x ?x)))) 'complete)))))
