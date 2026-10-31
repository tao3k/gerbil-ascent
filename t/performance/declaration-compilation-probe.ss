;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;;
;;; Matched public-engine probe for the declaration compilation refactor.
;;; Run the same file on a97762d and its parent ce86647.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-negation
                 gerbil-ascent-rule gerbil-ascent-program))

(def (name i)
  (string->symbol (string-append "r" (number->string i))))

(def (make-program depth)
  (let* ((x (gerbil-ascent-variable 'x))
         (relations
          (cons (gerbil-ascent-relation 'seed 1 '((7)))
                (map (lambda (i) (gerbil-ascent-relation (name i) 1 []))
                     (iota (+ depth 1)))))
         (rules
          (map (lambda (i)
                 (gerbil-ascent-rule
                  (list (gerbil-ascent-atom (name i) (list x)))
                  (list (gerbil-ascent-atom 'seed (list x))
                        (gerbil-ascent-negation (name (- i 1)) (list x)))))
               (map (lambda (i) (+ i 1)) (iota depth)))))
    (gerbil-ascent-program relations rules (+ depth 8) (+ depth 8)
                           (+ depth 8))))

(def (elapsed-ns thunk)
  (let (start (current-jiffy))
    (let (value (thunk))
      (cons (quotient (* (- (current-jiffy) start) 1000000000)
                      (jiffies-per-second))
            value))))

(def (check-run engine depth)
  (let* ((result (engine))
         (rows ((.ref result 'rows-of) (name depth)))
         (expected (if (odd? depth) '((7)) [])))
    (unless (equal? rows expected)
      (error "declaration probe changed rows" depth rows expected))))

(def (case-run depth)
  (let* ((programs (map (lambda (_) (make-program depth)) (iota 44)))
         (warm (car programs))
         (cold (cdr programs))
         (seed (gerbil-ascent-make-engine warm #t))
         (analysis (.ref seed '.analysis))
         (schema (.ref seed '.schema)))
    (unless (= (vector-ref (vector-ref analysis 3) (+ depth 1)) depth)
      (error "declaration probe did not construct strict strata" depth))
    (check-run (gerbil-ascent-make-engine warm #f analysis schema) depth)
    (displayln "CASE depth=" depth " samples=40")
    (force-output)
    (for-each
     (lambda (i)
       (let* ((fresh (list-ref cold i))
              (cold-sample (elapsed-ns
                            (lambda () (gerbil-ascent-make-engine fresh #f))))
              (warm-sample (elapsed-ns
                            (lambda () (gerbil-ascent-make-engine warm #f))))
              (state-sample
               (elapsed-ns
                (lambda () (gerbil-ascent-make-engine warm #f
                                                     analysis schema))))
              (solve-sample
               (elapsed-ns
                (lambda ()
                  (let (run (gerbil-ascent-make-engine warm #f
                                                       analysis schema))
                    (check-run run depth))))))
         (check-run (cdr cold-sample) depth)
         (check-run (cdr warm-sample) depth)
         (check-run (cdr state-sample) depth)
         (displayln "SAMPLE " depth " " i " cold=" (car cold-sample)
                    " warm=" (car warm-sample)
                    " state=" (car state-sample)
                    " solve=" (car solve-sample))
         (when (zero? (modulo (+ i 1) 5)) (force-output))))
     (iota 40))))

(for-each case-run '(8 32 64))
(displayln "OK")
(force-output)
(exit 0)
