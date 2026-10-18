;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/temporal/lens
 (prefix-in :gerbil-ascent/t/performance/temporal-contract/reference old-))
(export temporal-input temporal-workflow temporal-expected)
(def (temporal-input count edge-count repeats)
 (let* ((ids (map (lambda (n) (string->symbol (string-append "n" (number->string (+ n 1000))))) (iota count)))
        (events (map (lambda (id) (list id 0 0)) ids))
        (edges (map (lambda (n) (list (list-ref ids (quotient n count)) (list-ref ids (modulo n count))))
                    (iota edge-count))))
  (vector ids events edges repeats)))
(def (temporal-workflow old? input)
 (let ((make-lens (if old? old-temporal-lens temporal-lens))
       (make-source (if old? old-temporal-source temporal-source))
       (projection (if old? old-temporal-projection temporal-projection)))
  (let repeat ((left (vector-ref input 3)) (result []))
   (if (zero? left) result
    (repeat (- left 1)
     (list (projection (make-lens 0 'clock 0 10 0 'cut (vector-ref input 0) 0 #f))
           (projection (make-source 'source 0 'clock (vector-ref input 1) (vector-ref input 2)))))))))
(def (temporal-expected input)
 (list (list 0 'clock 0 10 0 'cut (vector-ref input 0) 0 #f)
       (list 'source 0 'clock (vector-ref input 1) (vector-ref input 2))))
