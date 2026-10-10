;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Checked temporal parent edges become dense IDs at this boundary. Symbols,
;;; including missing parents, retain eq? identity. Each invocation owns its
;;; identity table and adjacency; source rows are read without mutation.
(import (only-in :gerbil-ascent/core/dependency-graph
                 gerbil-ascent-graph-components))

(export temporal-cut-cyclic?)

;; temporal-cut-cyclic?
;;   : (-> (List (List Symbol)) Boolean)
;;   : (-> CheckedParentEdges CyclicCut)
;;   | doc m%
;;       Check the complete cut graph, including vertices without event data.
;;       Self edges are cycles; otherwise a strongly connected component with
;;       multiple vertices is cyclic. Private dense adjacency permits one
;;       linear graph traversal instead of a closure traversal for every edge.
;;       Time windows and evidence production belong to the caller.
;;
;;       # Examples
;;
;;       ```scheme
;;       (temporal-cut-cyclic? '((a b) (b a)))
;;       ;; => #t
;;       (temporal-cut-cyclic? '((a b) (a c) (b c)))
;;       ;; => #f
;;       ```
;;     %
(def (temporal-cut-cyclic? edges)
  (or (ormap (lambda (edge) (eq? (car edge) (cadr edge))) edges)
      (let ((ids (make-hash-table-eq)) (count 0))
        ;; Intern both endpoints: missing-parent frontiers must not erase
        ;; vertices from the cycle check. IDs belong only to this call.
        (def (intern id)
          (or (hash-get ids id)
              (let (index count)
                (hash-put! ids id index)
                (set! count (+ count 1))
                index)))
        (for-each (lambda (edge) (intern (car edge)) (intern (cadr edge))) edges)
        (let (successors (make-vector count []))
          (for-each
           (lambda (edge)
             (let ((from (hash-get ids (car edge)))
                   (to (hash-get ids (cadr edge))))
               (vector-set! successors from
                 (cons to (vector-ref successors from)))))
           edges)
          (ormap (lambda (component) (pair? (cdr component)))
                 (gerbil-ascent-graph-components successors))))))
