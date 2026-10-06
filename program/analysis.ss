;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Immutable declaration schema and rule-plan cache shared by evaluation engines.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-storage-extension))

(export gerbil-ascent-program-analysis
        gerbil-ascent-program-schema)

;; Program declarations are POO values. Their lowered rule plan is immutable
;; and can be shared; each evaluation still creates its own relation state.
(def +program-analysis-cache+
  (make-hash-table-eq weak-keys: #t lock: (make-mutex 'ascent-program-analysis)))
(def +program-schema-cache+
  (make-hash-table-eq weak-keys: #t lock: (make-mutex 'ascent-program-schema)))

;;; Primitive table access owns its lock. Declaration inspection and caller
;;; builders stay outside critical sections; failed builds publish nothing.
;; : (-> Program Relations Rules (-> Analysis) Analysis)
(def (gerbil-ascent-program-analysis program relations rules build)
  (let (cached (hash-get +program-analysis-cache+ program))
    (if (and cached
             (eq? relations (vector-ref cached 0))
             (eq? rules (vector-ref cached 1)))
      cached
      (let (fresh (build))
        (hash-put! +program-analysis-cache+ program fresh)
        fresh))))

;;; Schema cache keys include declaration identity, so replacing relations
;;; cannot reuse old names, arities, or provider dispatch slots.
;; : (-> Program Relations ProgramSchema)
(def (gerbil-ascent-program-schema program relations)
  (let (cached (hash-get +program-schema-cache+ program))
    (if (and cached (eq? relations (vector-ref cached 0)))
      cached
      (let* ((count (length relations))
             (names (make-vector count #f))
             (arity (make-vector count #f))
             (field-checkers (make-vector count #f))
             (positions (make-hash-table-eq))
             (index-providers (make-vector count #f))
             (storage-extensions (make-vector count #f))
             (lattice-joins (make-vector count #f))
             (kinds (make-vector count #f))
             (storage-providers (make-vector count #f)))
        (for-each
         (lambda (relation index)
           (let* ((name (.ref relation 'name))
                  (width (.ref relation 'arity))
                  (kind (.ref relation 'storage-kind))
                  (predicates (.ref relation 'field-predicates)))
             (unless (and (symbol? name) (not (hash-get positions name))
                          (exact-integer? width) (<= 0 width)
                          (memq kind '(relation lattice))
                          (or (eq? kind 'relation) (> width 0))
                          (list? predicates)
                          (or (null? predicates)
                              (= (length predicates) width))
                          (andmap procedure? predicates))
               (error "invalid or duplicate ASCENT relation" name))
             (vector-set! names index name)
             (vector-set! arity index width)
             (vector-set! kinds index kind)
             (hash-put! positions name (+ index 1))
             (when (pair? predicates)
               (vector-set! field-checkers index
                 (lambda (row)
                   (for-each
                    (lambda (predicate value)
                      (unless (predicate value)
                        (error "ASCENT relation field type mismatch"
                               name row)))
                    predicates row))))
             (vector-set! index-providers index
               (.ref relation 'index-provider))
             (if (eq? kind 'lattice)
               (let (join (.ref relation 'join))
                 (unless (procedure? join)
                   (error "invalid ASCENT lattice join" name))
                 (vector-set! lattice-joins index join))
               (let (provider (.ref relation 'storage-provider))
                 (vector-set! storage-providers index provider)
                 (vector-set! storage-extensions index
                   (gerbil-ascent-storage-extension provider width))))))
         relations (iota count))
        (let (fresh (vector relations names arity field-checkers positions
                            index-providers storage-extensions lattice-joins
                            kinds storage-providers))
          (hash-put! +program-schema-cache+ program fresh)
          fresh)))))
