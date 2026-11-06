;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Invocation-local ordered export. Packed flags replace a second UF graph;
;;; no replay matrix, emitted tuple or cursor is retained by the frozen cut.
(export gerbil-ascent-small-journal-export)
(defstruct replay-node (parent members size))
(defstruct replay-group (nodes roots values used width bits))
(def (root n) (if (replay-node-parent n) (root (replay-node-parent n)) n))
(def (position group a b) (##fx+ (##fx* a (replay-group-width group)) b))
(def (reaches? group a b)
  (let (p (position group (car (replay-node-members a)) (car (replay-node-members b))))
    (not (##fxzero? (##fxand (u16vector-ref (replay-group-bits group) (##fxarithmetic-shift-right p 4))
                         (##fxarithmetic-shift-left 1 (##fxand p 15)))))))
(def (mark! group a b)
  (let* ((p (position group a b)) (word (##fxarithmetic-shift-right p 4))
         (mask (##fxarithmetic-shift-left 1 (##fxand p 15))) (bits (replay-group-bits group)))
    (u16vector-set! bits word (##fxior (u16vector-ref bits word) mask))))
(def (fresh! group value)
  (let* ((id (replay-group-used group)) (n (make-replay-node #f (list id) 1)))
    (vector-set! (replay-group-values group) id value)
    (replay-group-used-set! group (+ id 1))
    (hash-put! (replay-group-nodes group) value n)
    (mark! group id id) n))
(def (group-key row)
  (match row
    ([left right] '(2 #f))
    ([group left right] (list 3 group))
    (else (list (length row) #f))))
;; Bound the temporary matrix before allocating it. Large sparse populations
;; keep the existing local-adjacency UF replay; they never allocate n^2 flags.
(def (prepare events rows-of)
  (let/cc fallback
    (def populations (make-hash-table))
    (def previous #f)
    (def (plan-value! nodes value)
      (unless (hash-key? nodes value)
        (when (= (hash-length nodes) 512) (fallback #f))
        (hash-put! nodes value #f)))
    (def (plan-row! row)
      (let* ((key (group-key row)) (arity (car key)))
        (unless (memq arity '(2 3)) (fallback #f))
        (let* ((nodes (or (hash-get populations key)
                         (let (nodes (make-hash-table))
                           (hash-put! populations key nodes) nodes)))
               (pair (if (= arity 3) (cdr row) row)))
          ;; Placeholder entries become replay nodes during admission. The
          ;; same bounded table owns planning and replay, with no second set.
          (plan-value! nodes (car pair))
          (plan-value! nodes (cadr pair)))))
    (for-each (lambda (event)
      (for-each (lambda (row)
        (unless (equal? previous row) (plan-row! row))
        (set! previous row)) (rows-of event))) events)
    (let (groups (make-hash-table))
      (hash-for-each (lambda (key nodes)
        (let (width (hash-length nodes))
          (hash-put! groups key (make-replay-group nodes []
            (make-vector width #f) 0 width
            (make-u16vector (quotient (+ (* width width) 15) 16) 0))))) populations)
      groups)))
(def (merge! group roots cycle)
  (let* ((winner (foldl (lambda (n best) (if (> (replay-node-size n) (replay-node-size best)) n best))
                       (car cycle) (cdr cycle)))
         (members (replay-node-members winner)) (size (replay-node-size winner)))
    (for-each (lambda (n)
      (unless (eq? n winner)
        (set! members (append (replay-node-members n) members))
        (set! size (+ size (replay-node-size n)))
        (replay-node-parent-set! n winner))) cycle)
    (replay-node-members-set! winner members)
    (replay-node-size-set! winner size)
    (replay-group-roots-set! group (filter (lambda (n) (not (replay-node-parent n))) roots))))
(def (write-rights! group prefix emit left rights)
  (unless (null? rights)
    (let (right (car rights))
      (mark! group left right)
      (when emit (emit (append prefix (list (vector-ref (replay-group-values group) left)
                                          (vector-ref (replay-group-values group) right))))))
    (write-rights! group prefix emit left (cdr rights))))
(def (write-block! group prefix emit lefts rights)
  (unless (null? lefts)
    (write-rights! group prefix emit (car lefts) rights)
    (write-block! group prefix emit (cdr lefts) rights)))
(def (count-targets group p succs count)
  (if (null? succs) count
    (let (s (car succs))
      (count-targets group p (cdr succs)
        (if (reaches? group p s) count
            (##fx+ count (##fx* (replay-node-size p) (replay-node-size s))))))))
(def (count-sources group preds succs count)
  (if (null? preds) count
    (count-sources group (cdr preds) succs (count-targets group (car preds) succs count))))
(def (write-targets! group p succs prefix emit)
  (unless (null? succs)
    (let (s (car succs))
      (unless (reaches? group p s)
        (write-block! group prefix emit (replay-node-members p) (replay-node-members s))))
    (write-targets! group p (cdr succs) prefix emit)))
(def (write-sources! group preds succs prefix emit)
  (unless (null? preds)
    (write-targets! group (car preds) succs prefix emit)
    (write-sources! group (cdr preds) succs prefix emit)))
;; Collect a fresh private spine in the writer order, leaving roots untouched.
(def (collect-roots roots selected? out)
  (if (null? roots) out
    (collect-roots (cdr roots) selected?
      (if (selected? (car roots)) (cons (car roots) out) out))))
(def (insert! group row budget consume)
  (let* ((pair (if (= (length row) 3) (cdr row) row))
         (nodes (replay-group-nodes group))
         (known-left (hash-get nodes (car pair))) (known-right (hash-get nodes (cadr pair)))
         (a (if known-left (root known-left) (fresh! group (car pair))))
         (b (if (equal? (car pair) (cadr pair)) a
              (if known-right (root known-right) (fresh! group (cadr pair))))))
    (if (and known-left known-right (reaches? group a b))
      (begin
        (when (< budget 0) (error "ASCENT trrel output fact budget exceeded"))
        (consume 0))
      (insert-components! group row budget consume a b
        (append (if known-left [] (list a))
                (if (or known-right (eq? a b)) [] (list b)))))))
;; Admit an existing closure fact before collecting either matrix axis. A zero
;; frontier still visits the synchronous count consumer; every journal entry
;; remains replayed and the original negative-budget rejection is preserved.
(def (insert-components! group row budget consume a b new)
  (let* ((roots (append new (replay-group-roots group)))
         (preds (if (memq a new) (list a)
                    (collect-roots roots (lambda (p) (reaches? group p a)) [])))
         (succs (if (memq b new) (list b)
                    (collect-roots roots (lambda (s) (reaches? group b s)) [])))
         (cycle (and (not (eq? a b)) (reaches? group b a)
                     (filter (lambda (p) (reaches? group b p)) (reverse preds))))
         (needed (count-sources group preds succs (length new)))
         (prefix (if (= (length row) 3) (list (car row)) []))
         (values (replay-group-values group)))
    (when (> needed budget) (error "ASCENT trrel output fact budget exceeded"))
    ;; Admission is decided once for the complete injection, before any rows
    ;; are emitted. Root-pair and member order match the UF frontier exactly.
    (let (emit (consume needed))
      (for-each (lambda (n)
        (when emit (let (v (vector-ref values (car (replay-node-members n))))
          (emit (append prefix (list v v)))))) new)
      ;; Each old component owns disjoint matrix rows/columns. Writing one
      ;; missing block cannot change the test for another block; roots/members
      ;; merge only after this traversal. Collecting both axes backward reproduces UF's
      ;; prepended change list without allocating that intermediate family.
      ;; These collected list spines are invocation-local; roots and journals
      ;; are never reversed in place. The emitted spine is likewise private.
      (write-sources! group preds succs prefix emit))
    (replay-group-roots-set! group roots)
    (when cycle (merge! group roots cycle))))
(def (gerbil-ascent-small-journal-export events kind-of rows-of budget skip delta?)
  (let (groups (prepare events rows-of))
    (and groups
      (let ((output []) (admitted 0) (previous #f) (injections (make-hash-table)))
        (for-each (lambda (event)
          (let ((batch []) (derived? (and (not delta?) (eq? (kind-of event) 'derived))))
            ;; Reuse the synchronous event writer. A repeated injection still
            ;; advances its zero-count transition without allocating a wrapper
            ;; or looking up its already admitted vertices again.
            (def emit
              (if derived? (lambda (stored) (set! batch (cons stored batch)))
                           (lambda (stored) (set! output (cons stored output)))))
            (def (consume needed)
              (let (next (+ admitted needed))
                (begin0 (and (> next skip)
                  (begin
                    (when (> skip admitted) (error "ASCENT ordered delta splits an injection frontier"))
                    emit))
                  (set! admitted next))))
            (for-each (lambda (row)
              (if (or (equal? previous row) (hash-get injections row))
                (consume 0)
                (begin (insert! (hash-get groups (group-key row)) row budget consume)
                       (when (< (hash-length injections) 256) (hash-put! injections row #t))))
              (set! previous row)) (rows-of event))
            (when derived? (set! output (append! (reverse! batch) output)))))
          (reverse events))
        (reverse! output)))))
