;;; -*- Gerbil -*-
;;; Original cached/cold algorithm from 099b381588360a8a49fd772f666a1a00351366f5.
(import (only-in ../object object-%precedence-list object-%precedence-list-set!
                 object-supers invalid-object-summary)
        (only-in :std/values first-value)
        (only-in :gerbil/runtime/c3 c4-linearize))
(export precedence-reference!)

(def (precedence-reference! self (heads '()))
  ;; Preserve the ordered heads for diagnostics while keeping the cycle guard
  ;; as private implementation state at this abstraction boundary.
  (def active (make-hash-table-eq))
  (for-each (lambda (head) (hash-put! active head #t)) heads)
  (let compute ((object self) (heads heads))
    (cond
     ((object-%precedence-list object))
     ((hash-key? active object)
      (error "Circular precedence graph" (member object heads)))
     (else
      (hash-put! active object #t)
      (let (precedence-list
            (first-value
             (c4-linearize
              [object] (object-supers object)
              get-precedence-list:
              (lambda (super) (compute super [object . heads]))
              eq: eq?
              get-name: invalid-object-summary)))
        (hash-remove! active object)
        (object-%precedence-list-set! object precedence-list)
        precedence-list)))))
