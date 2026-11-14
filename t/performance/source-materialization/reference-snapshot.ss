;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private source-only declaration preparation. Preparation is persistent:
;;; the caller adopts a cut only after evaluation and acceptance succeed.
(import (only-in :clan/poo/object .o .ref))
(export gerbil-ascent-source-snapshot gerbil-ascent-prepare-source-snapshot
        source-snapshot-program source-snapshot-rows)

;; : (forall (p d r) (-> p p d r (SourceSnapshot p)))
;; : (-> Program Program (List Relation) RowVector SourceSnapshot)
(defstruct source-snapshot (template program declarations rows))

;; : (forall (p) (-> p (SourceSnapshot p)))
;; : (-> Program SourceSnapshot)
(def (gerbil-ascent-source-snapshot program)
  (let (declarations (.ref program 'relations))
    (make-source-snapshot program program declarations
      (list->vector (map (lambda (relation) (.ref relation 'rows)) declarations)))))

;;; Row identity selects unchanged declaration views, not row validity. Fresh
;;; engines still admit every row, invoke field/provider checks and charge budgets.
;;; Changed views inherit the fixed template, keeping prototype depth bounded.
;; : (forall (p) (-> (SourceSnapshot p) RowVector (SourceSnapshot p)))
;; : (-> SourceSnapshot RowVector SourceSnapshot)
(def (gerbil-ascent-prepare-source-snapshot snapshot rows)
  (with ((source-snapshot template _ declarations previous) snapshot)
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
        (make-source-snapshot template (.o (:: @ template) relations: next) next rows)
        snapshot))))
