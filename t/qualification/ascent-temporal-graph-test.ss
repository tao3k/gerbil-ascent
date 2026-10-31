;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/temporal/graph temporal-cut-cyclic?))
(export ascent-temporal-graph-test)

;;; Independent Boolean matrix model, including the diagonal. It consumes the
;;; encoded graph mask, never the implementation's symbol-to-ID conversion.
(def (matrix-cyclic? mask)
  (let (matrix (make-vector 9 #f))
    (for-each (lambda (position)
                (vector-set! matrix position
                  (not (zero? (bitwise-and mask (arithmetic-shift 1 position))))))
              (iota 9))
    (for-each
     (lambda (via)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (+ (* from 3) via))
                        (vector-ref matrix (+ (* via 3) to)))
               (vector-set! matrix (+ (* from 3) to) #t)))
           (iota 3)))
        (iota 3)))
     (iota 3))
    (ormap (lambda (node) (vector-ref matrix (* node 4))) (iota 3))))

(def (mask-edges mask)
  (filter-map
   (lambda (position)
     (and (not (zero? (bitwise-and mask (arithmetic-shift 1 position))))
          (list (list-ref '(a b c) (quotient position 3))
                (list-ref '(a b c) (modulo position 3)))))
   (iota 9)))

(def ascent-temporal-graph-test
  (test-suite "temporal cut graph preflight"
    (test-case "all three-vertex graphs agree with independent matrix closure"
      (for-each
       (lambda (mask)
         (let ((edges (mask-edges mask)) (expected (matrix-cyclic? mask)))
           (check-equal? (temporal-cut-cyclic? edges) expected)
           (check-equal? (temporal-cut-cyclic? (reverse edges)) expected)
           (check-equal? edges (mask-edges mask)))
         (when (zero? (modulo (+ mask 1) 64))
           (displayln "TEMPORAL-GRAPH " (+ mask 1) "/512")
           (force-output)))
       (iota 512)))
    (test-case "the full parent-edge bound retains disconnected and long cycles"
      (let* ((nodes (map (lambda (n) (string->symbol (string-append "event-" (number->string n))))
                         (iota 513)))
             (chain (map list (take nodes 512) (cdr nodes))))
        (check-equal? (temporal-cut-cyclic? chain) #f)
        (check-equal? (temporal-cut-cyclic?
                       (cons (list (last nodes) (car nodes)) (take chain 511))) #f)
        (check-equal? (temporal-cut-cyclic?
                       (cons (list (list-ref nodes 511) (car nodes)) (take chain 511))) #t)
        (check-equal? (temporal-cut-cyclic?
                       (append (take chain 510) '((missing-a missing-b) (missing-b missing-a)))) #t)
        (check-equal? (temporal-cut-cyclic? chain) #f)))
    (test-case "fresh identity maps preserve symbol identity and source rows"
      (let* ((left (gensym 'same)) (right (gensym 'same))
             (edges (list (list left right))))
        (check-equal? (temporal-cut-cyclic? edges) #f)
        (check-equal? (temporal-cut-cyclic? (append edges (list (list right left)))) #t)
        (check-equal? (temporal-cut-cyclic? '((a a))) #t)
        (check-equal? (temporal-cut-cyclic? []) #f)
        (check-equal? (temporal-cut-cyclic? edges) #f)
        (check-equal? (caar edges) left)
        (check-equal? (cadar edges) right)))))
