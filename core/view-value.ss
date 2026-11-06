;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Frozen view values and invocation-local traversal protocols.
(import (only-in :std/list/list-builder with-list-builder))
(export
  (struct-out relation-view)
  (struct-out part-visitors)
  (struct-out rectangle-visitors)
  (struct-out row-stream)
  (struct-out rectangle)
  (struct-out rectangle-bucket)
  (struct-out rectangle-route)
  (struct-out rectangle-query)
  (struct-out rectangle-selection)
  gerbil-ascent-view-bind
  gerbil-ascent-view-with-export
  gerbil-ascent-for-each-row
  gerbil-ascent-any-row?
  gerbil-ascent-row-count
  gerbil-ascent-view-select
  gerbil-ascent-row-parts?
  gerbil-ascent-admitted-row-parts?
  gerbil-ascent-for-each-row-parts
  gerbil-ascent-visit-view-parts!
  gerbil-ascent-visit-admitted-view-parts!
  gerbil-ascent-view-contains?
  materialize-rows
  gerbil-ascent-view-rows)

(defstruct relation-view (identity generation revision lane count units visit contains export parts))
(defstruct part-visitors (checked admitted))
;; Built-in products additionally own a direct selected-result collector.
;; Custom visitors keep their existing callback and ordering protocol.
(defstruct (rectangle-visitors part-visitors) (materialize) final: #t)
(defstruct row-stream (view columns key))
(defstruct rectangle (prefix left right))
(defstruct rectangle-bucket (members blocks count plain) final: #t)
;; Query-local owner lookup. Each coordinate uses its first fixed constraint;
;; no cache or traversal state escapes into the immutable captured view.
(defstruct rectangle-route (routes))
(defstruct (rectangle-query rectangle-route) (axes bindings scan?) final: #t)
(defstruct rectangle-selection (ordinal block members) final: #t)
;; : (-> FrozenView Symbol SourceGeneration Natural Symbol FrozenView)
(def (gerbil-ascent-view-bind view identity generation revision lane)
  (make-relation-view identity generation revision lane (relation-view-count view)
    (relation-view-units view) (relation-view-visit view) (relation-view-contains view) (relation-view-export view) (relation-view-parts view)))
;; Private ordered export can replay a frozen injection cut without a tuple cache.
(def (gerbil-ascent-view-with-export view export)
  (make-relation-view (relation-view-identity view) (relation-view-generation view)
    (relation-view-revision view) (relation-view-lane view) (relation-view-count view)
    (relation-view-units view) (relation-view-visit view) (relation-view-contains view) export (relation-view-parts view)))
;; : (-> RowVisitor (Or Rows FrozenView RowStream) Void)
(def (gerbil-ascent-for-each-row consume rows)
  (cond ((relation-view? rows) ((relation-view-visit rows) [] [] consume))
        ((row-stream? rows) ((relation-view-visit (row-stream-view rows))
                            (row-stream-columns rows) (row-stream-key rows) consume))
        (else (for-each consume rows))))
;; : (-> RowPredicate (Or Rows FrozenView RowStream) Boolean)
(def (gerbil-ascent-any-row? predicate rows)
  (call/cc (lambda (done)
    (gerbil-ascent-for-each-row (lambda (row) (when (predicate row) (done #t))) rows) #f)))
;; : (-> (Or Rows FrozenView) Natural)
(def (gerbil-ascent-row-count rows)
  (if (relation-view? rows) (relation-view-count rows) (length rows)))
;; : (-> FrozenView Columns Key (Or FrozenView RowStream))
(def (gerbil-ascent-view-select view columns key)
  (if (and (null? columns) (null? key)) view
    (make-row-stream view columns key)))
;; Compiled consumers bind fields directly; no temporary Cartesian row is built.
;; : (-> RowSource Boolean)
(def (gerbil-ascent-row-parts? rows)
  (and (cond ((relation-view? rows) (relation-view-parts rows))
             ((row-stream? rows) (relation-view-parts (row-stream-view rows))) (else #f)) #t))
;; Checked custom visitors do not establish exact canonical key selection.
;; A mixed union retains that distinction through arbitrarily nested cuts.
(def (gerbil-ascent-admitted-row-parts? view)
  (and (relation-view? view)
       (let (parts (relation-view-parts view))
         (and (part-visitors? parts) (part-visitors-admitted parts) #t))))
;; : (-> PartVisitor RowSource Void)
(def (gerbil-ascent-for-each-row-parts consume rows)
  (if (relation-view? rows) (gerbil-ascent-visit-view-parts! rows [] [] consume)
    (gerbil-ascent-visit-view-parts! (row-stream-view rows)
      (row-stream-columns rows) (row-stream-key rows) consume)))
;; Synchronous indexed consumers own traversal. Custom parts retain the
;; checked three-argument protocol; built-in visitors carry admission separately.
;; : (-> FrozenView Columns Key PartVisitor Void)
(def (gerbil-ascent-visit-view-parts! view columns key consume)
  (let (parts (relation-view-parts view))
    ((if (part-visitors? parts) (part-visitors-checked parts) parts) columns key consume)))
;; Only the canonical compiled index owner supplies admitted columns and keys.
;; : (-> BuiltinView AdmittedColumns AdmittedKey PartVisitor Void)
(def (gerbil-ascent-visit-admitted-view-parts! view columns key consume)
  (unless (gerbil-ascent-admitted-row-parts? view)
    (error "ASCENT view lacks admitted parts"))
  ((part-visitors-admitted (relation-view-parts view)) columns key consume))
;; : (-> FrozenView Row Boolean)
(def (gerbil-ascent-view-contains? view row)
  ((relation-view-contains view) row))
;; : (-> FrozenView Rows)
(def (materialize-rows visit)
  ;; The invocation owns only this outer spine. Visitors control tuple
  ;; construction; frozen member and journal spines are never reversed.
  (with-list-builder (collect!)
    (visit collect!)))
;; Selected materialization shares the owned collector with fallback exports.
;; Complete export and explicit query have distinct ordering contracts.
(def gerbil-ascent-view-rows
  (case-lambda
    ((view)
     (if (relation-view-export view)
       ((relation-view-export view))
       (materialize-rows (cut (relation-view-visit view) [] [] <>))))
    ((view columns key)
     (let (parts (relation-view-parts view))
       (if (rectangle-visitors? parts)
         ((rectangle-visitors-materialize parts) columns key)
         (materialize-rows (cut (relation-view-visit view) columns key <>)))))))
;; : (-> Row Columns Key Boolean)
