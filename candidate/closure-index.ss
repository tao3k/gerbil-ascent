;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private lookup over one verified finite replay. Ordered rows remain the
;;; authority for enumeration and budget charging; membership never emits rows.
(export make-closure-index closure-index-rows closure-index-member? closure-index-source)
(defstruct closure-relation (rows members source))

;; : (-> VerifiedClosure SourceRelations ClosureIndex)
(def (make-closure-index closure (sources []))
  (let (index (make-hash-table-eq size: (length closure)))
    (for-each
     (lambda (entry)
       (let* ((rows (caddr entry)) (members (make-hash-table size: (length rows))))
         (for-each (lambda (row) (hash-put! members row #t)) rows)
         (hash-put! index (car entry) (make-closure-relation rows members #f))))
     closure)
    ;; Occurrence labels belong to the same relation metadata, not another
    ;; symbol table. Vector order includes duplicate source occurrences.
    (for-each (lambda (entry)
                (closure-relation-source-set! (closure-entry index (car entry))
                  (list->vector (caddr entry)))) sources)
    index))

;; : (-> ClosureIndex Symbol ClosureRelation)
(def (closure-entry index name)
  (or (hash-get index name) (error "candidate is missing inspected entry" name)))

;; : (-> ClosureIndex Symbol Rows)
(def (closure-index-rows index name)
  (closure-relation-rows (closure-entry index name)))

;; : (-> ClosureIndex Symbol GroundRow Boolean)
(def (closure-index-member? index name row)
  (and (hash-get (closure-relation-members (closure-entry index name)) row) #t))

;; : (-> ClosureIndex Symbol (Maybe SourceVector))
(def (closure-index-source index name)
  (let (entry (hash-get index name))
    (and entry (closure-relation-source entry))))
