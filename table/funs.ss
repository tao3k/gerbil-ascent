;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private index algorithms. The evaluator owns cache invalidation.

(export gerbil-ascent-index-build gerbil-ascent-index-extend! gerbil-ascent-index-order!
        gerbil-ascent-index-key gerbil-ascent-index-row-snapshot
        gerbil-ascent-index-row-snapshot/arity gerbil-ascent-index-batch!)

;;; Native update invokes the callback synchronously. Bind each row in the
;;; caller's key expression, while one private slot/callback belongs to the
;;; entire batch. Fresh cons cells preserve previously returned bucket spines.
;;; The index expression is evaluated once; key evaluation precedes publication.
;; : (-> Index Rows RowBinding KeyExpression Index)
(defrule (gerbil-ascent-index-batch! index rows row key)
  (let* ((target index) (row-slot (vector #f))
         (prepend-row (lambda (bucket) (cons (vector-ref row-slot 0) (or bucket [])))))
    (for-each (lambda (row)
      (let (selected key)
        (vector-set! row-slot 0 row)
        (hash-update! target selected prepend-row #f))) rows)
    target))

;;; Copy admitted outer/row spines while preserving field value identity.
;;; Build/extend callers already own admitted rows; lookup uses the arity protocol.
;; : (forall (v) (-> [[v]] [[v]]))
;; : (-> Rows DetachedRowSpines)
(def (gerbil-ascent-index-row-snapshot rows)
  (map (lambda (row) (map values row)) rows))

;;; Admit and detach the whole provider packet before membership or callbacks.
;;; The width bounds traversal even for cyclic/improper rows. Each copied
;;; suffix is admitted before its prefix is constructed; failed packets escape
;;; no row spines. Field values remain borrowed, including mutable values.
;; : (-> ProperRowPacket Nat DetachedRowSpines)
(def (gerbil-ascent-index-row-snapshot/arity rows width)
  (def (wrong-arity)
    (error "ASCENT index provider returned wrong row arity" width))
  (def (copy row left)
    (if (zero? left)
      (if (null? row) [] (wrong-arity))
      (match row
        ([value . rest] (cons value (copy rest (- left 1))))
        (else (wrong-arity)))))
  (map (cut copy <> width) rows))

;; : (-> (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-build rows columns)
  (let (index (make-hash-table))
    (gerbil-ascent-index-extend! index rows columns)
    (gerbil-ascent-index-order! index)))

;; gerbil-ascent-index-order!
;; : (forall (k r) (-> (HashTable k [r]) (HashTable k [r])))
;; : (-> FreshOwnedBuckets OrderedIndex)
;; | doc m%
;;     Restore source order only in freshly constructed private bucket spines.
;;     Rows and keys remain caller-owned; existing published indexes must never
;;     pass through this operation. Singleton buckets already have source order.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-index-order! fresh-index)
;;     ;; => the same index with each owned bucket in source order
;;     ```
;;   %
(def (gerbil-ascent-index-order! index)
  (hash-for-each
   (lambda (key rows)
     (when (pair? (cdr rows))
       (hash-put! index key (reverse! rows)))) index)
  index)

;;; Build distances only for nondecreasing columns. A false suffix
;;; rejects the whole layout before allocating a partial distance spine.
;;; Each result belongs to this call/batch; caller-owned columns are never cached.
;; : (-> Columns (Maybe [Nat]))
;; | doc m%
;;     Return a fresh ordered distance spine or false for reordered columns.
;;     Zero distances reread fields; rejection publishes no partial layout.
;;
;;     # Examples
;;
;;     ```scheme
;;     (forward-column-steps '(0 0 2))
;;     ;; => (0 0 2)
;;     ```
;;   %
(def (forward-column-steps columns)
  (let step ((remaining columns) (position 0))
    (match remaining
      ([] [])
      ([column . rest]
       (and (>= column position)
            (alet (steps (step rest column))
              (cons (inexact->exact (- column position)) steps)))))))

;;; Single-key consumers validate without retaining a distance layout. The
;;; empty tuple is ordered; nonnegative integral inexact positions normalize
;;; at field selection, retaining the existing public ordered-key convention.
;; : (-> Columns Boolean)
(def (nondecreasing-columns? columns)
  (let ordered ((remaining columns) (position 0))
    (match remaining
      ([] #t)
      ([column . rest] (and (>= column position) (ordered rest column))))))

;;; Both consumers share field publication; parameter identifiers are hygienic.
;;; Distance and the row are observed only for a selected field, once per step.
;; : (-> Row Selections Bindings DistanceExpression NextExpression Key)
(defrule (forward-key-step row selections (column rest selected) distance next)
  (match selections
    ([] [])
    ([column . rest]
     (let (selected (list-tail row distance))
       (cons (car selected) next)))))
;; : (-> Row [Nat] Key)
(def (stepped-key row steps)
  (forward-key-step row steps (distance rest selected) distance
    (stepped-key selected rest)))
;; : (-> Row Columns Nat Key)
(def (column-key row columns position)
  (forward-key-step row columns (column rest selected)
    (inexact->exact (- column position)) (column-key selected rest column)))

;;; Recompute admission for each call; columns remain caller-owned. Single-key
;;; consumers stream gaps, while a batch retains only its shared distance spine.
;; : (-> Row (List ColumnIndex) Key)
;; : (forall (v) (-> [v] [Nat] [v]))
;; | doc m%
;;     Project current columns in order, preserving repeated fields and their
;;     identities. Each call owns its cursor; no caller metadata is cached.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-index-key '(#f 2 3) '(0 0 2))
;;     ;; => (#f #f 3)
;;     ```
;;   %
(def (gerbil-ascent-index-key row columns)
  (if (nondecreasing-columns? columns)
    (column-key row columns 0)
    (map (lambda (column) (list-ref row column)) columns)))

;; : (-> Index (List Row) (List ColumnIndex) Index)
(def (gerbil-ascent-index-extend! index new-rows columns)
  ;; Select the complete batch loop once. Distances retain no row state.
  ;; The synchronous native update and its private row slot preserve published
  ;; bucket spines; unordered projection still observes each current column.
  (cond
    ((forward-column-steps columns) =>
     (lambda (steps)
       (gerbil-ascent-index-batch! index new-rows row (stepped-key row steps))))
    (else
     (gerbil-ascent-index-batch! index new-rows row
       (map (lambda (column) (list-ref row column)) columns)))))
