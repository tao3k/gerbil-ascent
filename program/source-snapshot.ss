;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private source-only declaration preparation. Preparation is persistent:
;;; the caller adopts a cut only after evaluation and acceptance succeed.
(import (only-in :clan/poo/object .o .ref)
        (only-in :std/iter for in-range)
        (only-in "source-log.ss" gerbil-ascent-source-log-rows)
        (only-in "scheme-checked.ss" relational-scalar?))
(export gerbil-ascent-source-snapshot gerbil-ascent-prepare-source-snapshot
        gerbil-ascent-prepare-source-log-snapshot
        gerbil-ascent-source-log-snapshot-equal?
        gerbil-ascent-source-snapshot-scalar?
        source-snapshot-program source-snapshot-rows)

;; : (forall (p d r m) (-> p p d r m (SourceSnapshot p)))
;; : (-> Program Program [Relation] RowVector MaterializationVector SourceSnapshot)
(defstruct source-snapshot (template program declarations rows materializations) final: #t)
(defstruct source-materialization (base additions rows scalar?) final: #t)

;;; The thunk captures only owned read-only rows, never a previous cut. Scalar
;;; classification invokes no user code and does not replace row admission.
;; : (forall (r) (-> [r] [r] [r] (SourceMaterialization r)))
;; : (-> SourceBase ReversedAdditions OrderedSourceRows SourceMaterialization)
(def (capture-source-materialization base additions rows)
  (make-source-materialization base additions rows
    (delay-atomic (andmap (cut andmap relational-scalar? <>) rows))))

;; : (forall (r) (-> [r] [r] (SourceMaterialization r) (SourceMaterialization r)))
;; : (-> SourceBase ReversedAdditions SourceMaterialization SourceMaterialization)
(def (materialize-source-log base additions (previous :- source-materialization))
  (if (and (eq? base previous.base) (eq? additions previous.additions)) previous
    (capture-source-materialization base additions
      (gerbil-ascent-source-log-rows base additions))))

;;; Exact root evidence avoids a second value scan; it cannot certify a
;;; foreign candidate, a stale log or a different materialized row spine.
;; : (forall (p r) (-> (SourceSnapshot p) p Natural (SourceLog r) [r] Boolean))
;; : (-> SourceSnapshot Program Natural SourceLog Rows Boolean)
(def (gerbil-ascent-source-log-snapshot-equal? (snapshot :- source-snapshot)
                                             candidate index log rows)
  (and (eq? candidate snapshot.program)
       (using (materialization (vector-ref snapshot.materializations index) :- source-materialization)
         (and (eq? (car log) materialization.base)
              (eq? (cdr log) materialization.additions)
              (eq? rows materialization.rows)))))

;; : (forall (p r) (-> (SourceSnapshot p) p Natural [r] Boolean))
;; : (-> SourceSnapshot Program Natural Rows Boolean)
(def (gerbil-ascent-source-snapshot-scalar? (snapshot :- source-snapshot) candidate index rows)
  (and (eq? candidate snapshot.program)
       (using (materialization (vector-ref snapshot.materializations index) :- source-materialization)
         (and (eq? rows materialization.rows) (force materialization.scalar?)))))

;; : (forall (p) (-> p (SourceSnapshot p)))
;; : (-> Program SourceSnapshot)
(def (gerbil-ascent-source-snapshot program)
  (let (declarations (.ref program 'relations))
    (let (rows (list->vector (map (lambda (relation) (.ref relation 'rows)) declarations)))
      (make-source-snapshot program program declarations rows
        (vector-map (lambda (base) (capture-source-materialization base [] base)) rows)))))

;;; Row identity selects unchanged declaration views, not row validity. Fresh
;;; engines still admit every row, invoke field/provider checks and charge budgets.
;;; Changed views inherit the fixed template, keeping prototype depth bounded.
;; : (forall (p) (-> (SourceSnapshot p) RowVector (SourceSnapshot p)))
;; : (-> SourceSnapshot RowVector SourceSnapshot)
(def (gerbil-ascent-prepare-source-snapshot snapshot rows)
  (prepare-source-snapshot snapshot rows
    (vector-map (lambda (base) (capture-source-materialization base [] base)) rows) #f))

;;; Share only exact persistent log roots, never mutable source-state headers.
;;; Preparation owns new records and remains provisional until caller adoption.
;;; Fresh engine admission still checks every row and charges every occurrence.
;; : (forall (p r) (-> (SourceSnapshot p) (Vector (SourceLog r)) (SourceSnapshot p)))
;; : (-> SourceSnapshot SourceLogVector SourceSnapshot)
(def (gerbil-ascent-prepare-source-log-snapshot (snapshot :- source-snapshot) logs)
  (unless (= (vector-length logs) (vector-length snapshot.rows))
    (error "invalid ASCENT source snapshot width"))
  (let ((rows (make-vector (vector-length logs)))
        (materializations (make-vector (vector-length logs)))
        (changed? #f))
    (for (index (in-range (vector-length logs)))
      (with ([base . additions] (vector-ref logs index))
        (let (previous (vector-ref snapshot.materializations index))
          (using (next (materialize-source-log base additions previous) :- source-materialization)
            (unless (eq? next previous) (set! changed? #t))
            (vector-set! materializations index next)
            (vector-set! rows index next.rows)))))
    (if changed? (prepare-source-snapshot snapshot rows materializations #t) snapshot)))

;; : (-> SourceSnapshot RowVector MaterializationVector Boolean SourceSnapshot)
(def (prepare-source-snapshot snapshot rows materializations roots-changed?)
  (with ((source-snapshot template program declarations previous _) snapshot)
    (unless (= (vector-length rows) (vector-length previous))
      (error "invalid ASCENT source snapshot width"))
    (let* ((changed? #f)
           (next (map (lambda (prototype declaration index)
                        (let (replacement (vector-ref rows index))
                          (if (eq? replacement (vector-ref previous index))
                            declaration
                            (begin
                              (set! changed? #t)
                              (.o (:: @ prototype) rows: replacement)))))
                      (.ref template 'relations) declarations
                      (iota (vector-length rows)))))
      (if changed?
        (make-source-snapshot template (.o (:: @ template) relations: next) next rows materializations)
        (if roots-changed?
          (make-source-snapshot template program declarations previous materializations)
          snapshot)))))
