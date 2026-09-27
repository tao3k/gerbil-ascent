;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Per-relation transitive closure state. Only incoming edges are indexed;
;;; emitted closure rows stay in the fact set for duplicate suppression.
(export gerbil-ascent-trrel-state
        gerbil-ascent-trrel-extension
        gerbil-ascent-trrel-uf-extension)

(def (gerbil-ascent-trrel-state)
  (vector (make-hash-table) (make-hash-table) (make-hash-table)
          (make-hash-table) 0))

(def (gerbil-ascent-trrel-extend state row budget reflexive?)
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT trrel requires two or three columns" row)))
         (group (if (= width 3) (car row) #f))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair))
         (right (cadr pair))
         (known (vector-ref state 0))
         (new-edge? (not (hash-get known row)))
         (predecessors (vector-ref state 1))
         (successors (vector-ref state 2))
         (added [])
         (planned #f)
         (planned-count 0)
         (safe-budget? #f))
    (def (node-key node)
      (if (= width 3) (cons group node) node))
    (def (reach root arcs)
      (let* ((seen (vector-ref state 3))
             (mark (+ 1 (vector-ref state 4)))
             (todo (list root))
             (nodes []))
        (vector-set! state 4 mark)
        (let loop ()
          (unless (null? todo)
            (let (node (car todo))
              (set! todo (cdr todo))
              (unless (equal? (hash-get seen node) mark)
                (hash-put! seen node mark)
                (set! nodes (cons node nodes))
                (for-each
                 (lambda (neighbor)
                   (unless (equal? (hash-get seen neighbor) mark)
                     (set! todo (cons neighbor todo))))
                 (or (hash-get arcs (node-key node)) []))))
            (loop)))
        nodes))
    (def (emit! from to)
      (let (fact (if (= width 3)
                  (list group from to)
                  (list from to)))
        (unless (or (hash-get known fact)
                    (and planned (hash-get planned fact)))
          (unless safe-budget?
            (set! planned-count (+ planned-count 1))
            (when (> planned-count budget)
              (error "ASCENT trrel output fact budget exceeded"))
            (hash-put! planned fact #t))
          (when safe-budget? (hash-put! known fact #t))
          (set! added (cons fact added)))))
    (let ((from-nodes (if new-edge? (reach left predecessors) []))
          (to-nodes (if new-edge? (reach right successors) [])))
      ;; A loose upper bound avoids an allocation and preflight pass for the
      ;; common case while still proving that no budget failure can occur.
      (set! safe-budget?
        (<= (+ (* (length from-nodes) (length to-nodes))
               (if reflexive? 2 0))
            budget))
      (unless safe-budget? (set! planned (make-hash-table)))
      (when new-edge?
        (for-each
         (lambda (from)
           (for-each
            (lambda (to)
              (when (or (not (equal? from to))
                        (and (equal? left right) (equal? from left)))
                (emit! from to)))
            to-nodes))
         from-nodes)))
    (when reflexive?
      (emit! left left)
      (emit! right right))
    ;; Commit only after all new rows fit the caller's budget.
    (unless safe-budget?
      (for-each (lambda (fact) (hash-put! known fact #t)) added))
    (when new-edge?
      (let ((left-key (node-key left))
            (right-key (node-key right)))
        (hash-put! successors left-key
                   (cons right (or (hash-get successors left-key) [])))
        (hash-put! predecessors right-key
                   (cons left (or (hash-get predecessors right-key) [])))))
    (reverse added)))

(def (gerbil-ascent-trrel-extension state _all _pending row budget)
  (gerbil-ascent-trrel-extend state row budget #f))

(def (gerbil-ascent-trrel-uf-extension state _all _pending row budget)
  (gerbil-ascent-trrel-extend state row budget #t))
