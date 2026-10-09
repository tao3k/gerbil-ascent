;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/operator-descriptor
 :gerbil-ascent/program/operator-change
 (prefix-in :gerbil-ascent/t/performance/delta-sets/reference old-))
(export delta-input delta-workflow delta-expected delta-same-set?)
(def (delta-input width shape)
 (if (eq? shape 'chain)
  (vector
   (relational-op-function 2 (lambda (edge)
    (relational-op-fix 2 (lambda (path)
     (relational-op-union edge
      (relational-op-project (relational-op-join path edge 1 0) '(0 3)))))))
   (map (lambda (i) (list i (+ i 1))) (iota (- width 1)))
   (list (list (- width 1) width)))
 (let* ((before (map list (iota width)))
        (added (case shape
          ((empty) [])
          ((duplicate) (map list (iota width)))
          (else (map list (iota width (quotient width 2))))))
        (transform (relational-op-function 1 (lambda (input)
          (case shape
            ((fix) (relational-op-fix 1 (lambda (p) (relational-op-union p input))))
            (else (relational-op-project input '(0))))))))
  (vector transform before added))))
(def (delta-workflow old? input)
 (call-with-values (lambda ()
  ((if old? old-relational-op-delta-change relational-op-delta-change)
   (vector-ref input 0) (vector-ref input 1) (vector-ref input 2))) list))
;; Independent list-only oracle, outside the timed evaluator call.
(def (delta-expected input)
 (def (paths n)
  (apply append (map (lambda (from)
   (map (lambda (to) (list from to)) (iota (- n from) (+ from 1)))) (iota n))))
 (if (and (pair? (vector-ref input 1)) (= (length (car (vector-ref input 1))) 2))
  (let* ((n (length (vector-ref input 1))) (base (paths n)) (grown (paths (+ n 1))))
   (list base grown (filter (lambda (row) (= (cadr row) (+ n 1))) grown)))
 (let* ((base (vector-ref input 1))
        (delta (filter (lambda (row) (not (member row base))) (vector-ref input 2))))
  (list base (append base delta) delta))))
(def (delta-same-set? actual expected)
 (and (= (length actual) (length expected))
  (andmap (lambda (x y)
   (and (= (length x) (length y)) (andmap (lambda (row) (and (member row y) #t)) x))) actual expected)))
