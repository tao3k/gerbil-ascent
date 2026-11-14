;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/core/rectangle-geometry collect-rectangle-product))
(export ascent-rectangle-kernel-test)

;; Keep the pre-change pattern loop as an independent observable reference.
(def (reference lefts rights emit)
  (let outer ((pending lefts))
    (match pending
      ([] (void))
      ([left . tail]
       (let inner ((remaining rights))
         (match remaining
           ([] (outer tail))
           ([right . rest]
            (emit (list left right))
            (inner rest))))))))

(def (current lefts rights emit)
  (collect-rectangle-product left right lefts rights emit (list left right)))

(def (observe kernel lefts rights (fail-at #f))
  (let ((rows []) (calls 0))
    (let (status
           (with-catch
             (lambda (exception)
               (list 'failed (error-message exception) (error-irritants exception)))
             (lambda ()
               (kernel lefts rights
                 (lambda (row)
                   (set! calls (+ calls 1))
                   (when (equal? calls fail-at) (error "injected consumer failure"))
                   (set! rows (cons row rows))))
               'complete)))
      (list status calls (reverse rows)))))

(def ascent-rectangle-kernel-test
  (test-suite "Rectangle loop preserves proper and rejected traversal"
    (test-case "one thousand ordered products match the prior loop"
      (for-each
        (lambda (seed)
          (let ((lefts (map (lambda (n) (modulo (+ n seed) 7))
                           (iota (modulo seed 17))))
                (rights (map (lambda (n) (- seed n))
                            (iota (modulo seed 19)))))
            (check-equal? (observe current lefts rights)
                          (observe reference lefts rights))))
        (iota 1000)))
    (test-case "improper axes preserve emitted prefix and error"
      (for-each
        (lambda (lefts)
          (for-each
            (lambda (rights)
              (check-equal? (observe current lefts rights)
                            (observe reference lefts rights)))
            (list [] '(1 2) '(1 . bad) 'bad)))
        (list [] '(3 4) '(3 . bad) 'bad)))
    (test-case "consumer failure preserves exactly the same prefix"
      (for-each
        (lambda (stop)
          (check-equal? (observe current '(3 2 1) '(4 5 6) stop)
                        (observe reference '(3 2 1) '(4 5 6) stop)))
        (iota 11)))))
