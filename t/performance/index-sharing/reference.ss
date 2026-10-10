;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Finite logical column requirements share curried physical chains. Planning
;;; owns no rows. Each engine/worker builds and extends its own physical roots.
(export gerbil-ascent-index-sharing-layout
        gerbil-ascent-shared-index-build gerbil-ascent-shared-index-extend!
        gerbil-ascent-shared-index-rows)

;;; Maximum bipartite matching on strict subset edges yields a chain cover.
;;; Only chains with multiple logical requirements change physical storage;
;;; singleton chains retain the existing specialized hash representation.
;; : (-> ColumnRequirements IndexSharingLayout)
(def (gerbil-ascent-index-sharing-layout requirements)
  (let* ((unique (make-hash-table))
         (sets (begin
                 (for-each
                  (lambda (columns)
                    (unless (and (list? columns)
                                 (andmap (lambda (n) (and (exact-integer? n) (>= n 0))) columns))
                      (error "invalid index sharing columns" columns))
                    (let (ordered (list-sort < columns))
                      (unless (= (length ordered) (hash-length (let (seen (make-hash-table-eq)) (for-each (lambda (c) (hash-put! seen c #t)) ordered) seen)))
                        (error "repeated index sharing columns" columns))
                      (unless (null? ordered) (hash-put! unique ordered #t)))) requirements)
                 (list->vector (hash-keys unique))))
         (count (vector-length sets))
         (left (make-vector count #f)) (right (make-vector count #f))
         (layout (make-hash-table)))
    (def (below? i j)
      (let ((a (vector-ref sets i)) (b (vector-ref sets j)))
        (and (< (length a) (length b)) (andmap (cut member <> b) a))))
    (def (augment! i visited)
      (let search ((j 0))
        (and (< j count)
             (if (and (below? i j) (not (vector-ref visited j)))
               (begin
                 (vector-set! visited j #t)
                 (let (prior (vector-ref right j))
                   (if (or (not prior) (augment! prior visited))
                     (begin (vector-set! left i j) (vector-set! right j i) #t)
                     (search (+ j 1)))))
               (search (+ j 1))))))
    (for-each (lambda (i) (augment! i (make-vector count #f))) (iota count))
    (for-each
     (lambda (i)
       (unless (vector-ref right i)
         (let chain ((j i) (members []) (permutation []))
           (let* ((columns (vector-ref sets j))
                  (next (vector-ref left j))
                  (extended (append permutation
                                    (filter (lambda (c) (not (member c permutation))) columns)))
                  (covered (cons columns members)))
             (if next
               (chain next covered extended)
               (when (pair? (cdr covered))
                 (for-each (lambda (c) (hash-put! layout c extended)) covered)))))))
     (iota count))
    layout))

(defstruct shared-index (columns root ordinal views))
;;; Trie nodes retain either child maps or occurrence lists at full depth.
;;; Each occurrence has one increasing ordinal, so prefix traversal can restore
;;; exact relation order independently of hash traversal order and duplicates.
;; : (-> AdmittedRows NonemptyDistinctColumns SharedIndex)
(def (gerbil-ascent-shared-index-build rows columns)
  (let (index (make-shared-index columns (make-hash-table) 0 (make-hash-table)))
    (gerbil-ascent-shared-index-extend! index (reverse rows))
    index))

;; : (-> SharedIndex AdmittedInsertionRows SharedIndex)
(def (gerbil-ascent-shared-index-extend! index rows)
  ;; Old result spines remain immutable. One successful batch invalidates all
  ;; aliases together; there is no shared mutable bucket between engine owners.
  (when (pair? rows) (shared-index-views-set! index (make-hash-table)))
  (for-each
   (lambda (row)
     (let (ordinal (+ (shared-index-ordinal index) 1))
       (let insert ((node (shared-index-root index)) (columns (shared-index-columns index)))
         (let ((key (list-ref row (car columns))))
           (if (null? (cdr columns))
             (hash-put! node key (cons (cons ordinal row) (or (hash-get node key) [])))
             (let (child (or (hash-get node key)
                            (let (fresh (make-hash-table)) (hash-put! node key fresh) fresh)))
               (insert child (cdr columns))))))
       (shared-index-ordinal-set! index ordinal))) rows)
  index)

;;; Logical key order may differ from the physical prefix permutation. Resolve
;;; that adapter without changing caller columns, keys, rows or published lists.
;; : (-> SharedIndex LogicalPrefixColumns LogicalKey OrderedRows)
(def (gerbil-ascent-shared-index-rows index columns key)
  (let (physical (shared-index-columns index))
    (unless (= (length columns) (length key)) (error "shared index key arity mismatch"))
    ;; Evaluate logical terms before entering this adapter. Reordering values
    ;; must never reorder expression callbacks or cache their results.
    (def (already-ordered? logical remaining)
      (or (null? logical)
          (and (pair? remaining) (= (car logical) (car remaining))
               (already-ordered? (cdr logical) (cdr remaining)))))
    (def (value-of column logical values)
      (cond ((null? logical) (error "logical index is not a physical prefix" columns physical))
            ((= column (car logical)) (car values))
            (else (value-of column (cdr logical) (cdr values)))))
    (def (adapt remaining count)
      (if (= count 0) []
        (cons (value-of (car remaining) columns key) (adapt (cdr remaining) (- count 1)))))
    (def (collect node remaining)
      (let (records [])
        (hash-for-each
         (lambda (_ child)
           (set! records (append (if (null? (cdr remaining)) child
                                    (collect child (cdr remaining))) records))) node)
        records))
    (let* ((physical-key (if (already-ordered? columns physical) key
                            (adapt physical (length columns))))
           (cached (hash-get (shared-index-views index) physical-key)))
      (if cached (cdr cached)
        (let (rows
              (let lookup ((node (shared-index-root index)) (remaining physical) (key physical-key))
                (if (null? key)
                  (map cdr (list-sort (lambda (a b) (> (car a) (car b))) (collect node remaining)))
                  (let (child (hash-get node (car key)))
                    (if (not child) []
                      (if (null? (cdr remaining)) (map cdr child)
                        (lookup child (cdr remaining) (cdr key))))))))
          (hash-put! (shared-index-views index) physical-key (cons #t rows))
          rows)))))
