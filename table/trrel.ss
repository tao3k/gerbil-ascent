;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Per-relation transitive closure state. Index emitted reachability pairs so
;;; a new edge combines its known predecessors and successors directly.

(import (only-in "trrel-uf.ss" gerbil-ascent-trrel-uf-extension))

(export gerbil-ascent-trrel-state
        gerbil-ascent-trrel-extension
        gerbil-ascent-trrel-uf-extension)

;;; The public constructor returns an opaque provider state. Its private
;;; record names the membership and directional indexes; each run owns all
;;; three tables and extension functions alone update their contents.
(defstruct trrel-state (known predecessors successors))

;; : (-> TransitiveClosureState)
(def (gerbil-ascent-trrel-state)
  (make-trrel-state (make-hash-table) (make-hash-table) (make-hash-table)))

;;; A loose product bound admits the common path without a planning table.
;;; The uncertain path preflights all rows before mutating retained indexes.
;; : (-> TransitiveClosureState Row Nat Boolean Rows)
(def (gerbil-ascent-trrel-extend state row budget reflexive?)
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT trrel requires two or three columns" row)))
         (group (if (= width 3) (car row) #f))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair))
         (right (cadr pair))
         (known (trrel-state-known state))
         (new-edge? (not (hash-get known row)))
         (predecessors (trrel-state-predecessors state))
         (successors (trrel-state-successors state))
         (added [])
         (planned #f)
         (planned-count 0)
         (safe-budget? #f))
    (def (node-key node)
      (if (= width 3) (cons group node) node))
    (def (fact from to)
      (if (= width 3) (list group from to) (list from to)))
    (def (with-root node neighbors)
      (if (hash-get known (fact node node))
        neighbors
        (cons node neighbors)))
    (def (commit-fact! row)
      (let* ((pair (if (= width 3) (cdr row) row))
             (from (car pair))
             (to (cadr pair))
             (from-key (node-key from))
             (to-key (node-key to)))
        (hash-put! known row #t)
        (hash-put! successors from-key
                   (cons to (or (hash-get successors from-key) [])))
        (hash-put! predecessors to-key
                   (cons from (or (hash-get predecessors to-key) [])))))
    (def (emit! from to)
      (let (row (fact from to))
        (unless (or (hash-get known row)
                    (and planned (hash-get planned row)))
          (unless safe-budget?
            (set! planned-count (+ planned-count 1))
            (when (> planned-count budget)
              (error "ASCENT trrel output fact budget exceeded"))
            (hash-put! planned row #t))
          (when safe-budget? (commit-fact! row))
          (set! added (cons row added)))))
    (let ((from-nodes
           (if new-edge?
             (with-root left (or (hash-get predecessors (node-key left)) []))
             []))
          (to-nodes
           (if new-edge?
             (with-root right (or (hash-get successors (node-key right)) []))
             [])))
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
      (for-each commit-fact! added))
    (reverse added)))

;; : (-> TransitiveClosureState Rows Rows Row Nat Rows)
(def (gerbil-ascent-trrel-extension state _all _pending row budget)
  (gerbil-ascent-trrel-extend state row budget #f))
