;;; -*- Gerbil -*-
(import :gerbil-ascent/core/positive-plan
 (prefix-in :gerbil-ascent/t/performance/positive-traversal/reference old-))
(export traversal-input traversal-workflow traversal-expected)
(def (traversal-input width count shape)
 (let* ((terms (map (lambda (n) (cons 'variable (string->symbol (number->string n)))) (iota width)))
        (head (vector 'out terms))
        (body (list (vector 'atom (vector 'input terms []))))
        (heads (if (eq? shape 'multiple) (list head head) (list head)))
        (rows (map (lambda (_) (iota width)) (iota count))))
  (vector (old-gerbil-ascent-compile-positive-plan heads body)
          (gerbil-ascent-compile-positive-plan heads body) rows
          (* count (length heads) (foldl + 0 (iota width))))))
(def (traversal-workflow old? input)
 (let ((sum 0) (plan (vector-ref input (if old? 0 1)))
       (rows (vector-ref input 2)))
  ((if old? old-gerbil-ascent-run-positive-plan! gerbil-ascent-run-positive-plan!)
    plan (make-vector (vector-ref plan 2) #f) -1
    (lambda (_ frame delta keys) rows)
    (lambda (_ row) (set! sum (+ sum (foldl + 0 row))))) sum))
(def (traversal-expected input) (vector-ref input 3))
