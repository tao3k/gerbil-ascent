;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/operator-descriptor
 :gerbil-ascent/program/operator-reference :gerbil-ascent/program/operator-change
 (prefix-in :gerbil-ascent/t/performance/mapping-lookup/reference old-))
(export mapping-input mapping-workflow mapping-expected mapping-same-set?)
(def (mapping-input width shape)
 (def entries
  (case shape
   ((fix) (map (lambda (i) (list (list i) (list (+ i 1))))
            (append (iota (- width 1)) (iota (- width 1) width))))
   ((fanout) (apply append (map (lambda (i)
                (map (lambda (j) (list (list i) (list (+ (* i 4) j)))) (iota 4))) (iota width))))
   (else (map (lambda (i) (list (list i) (list (+ i 1)))) (iota width)))))
 (def before
  (case shape
   ((fix single small) '((0)))
   ((empty) [])
   ((miss) (map list (iota width (- width))))
   (else (map list (iota (quotient width 2))))))
 (def added
  (case shape
   ((fix) (list (list width)))
   ((single empty) [])
   ((small) '((1)))
   ((miss) (map list (iota width (- (* width 2)))))
   (else (map list (iota (- width (quotient width 2)) (quotient width 2))))))
 (def transformer
  (relational-op-function 1 (lambda (input)
   (case shape
    ((identity) (relational-op-project input '(0)))
    ((fix) (relational-op-fix 1 (lambda (p)
      (relational-op-union input (relational-op-flatmap p 1 entries)))))
    (else (relational-op-flatmap input 1 entries))))))
 (vector transformer before added))
(def (mapping-workflow old? input)
 (call-with-values (lambda ()
  ((if old? old-relational-op-delta-change relational-op-delta-change)
   (vector-ref input 0) (vector-ref input 1) (vector-ref input 2))) list))
;; The independent semantic interpreter never uses this lookup implementation.
(def (mapping-expected input)
 (call-with-values (lambda ()
  (relational-op-reference-change (vector-ref input 0) (vector-ref input 1) (vector-ref input 2))) list))
(def (mapping-same-set? actual expected)
 (and (= (length actual) (length expected))
  (andmap (lambda (x y)
   (and (= (length x) (length y)) (andmap (lambda (row) (and (member row y) #t)) x))) actual expected)))
