;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Immutable SCC execution metadata. Construction owns temporary grouping
;;; tables; returned components share admitted slot actions, never worker state.
(import (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?))
(export gerbil-ascent-positive-components gerbil-ascent-compile-positive-components
        gerbil-ascent-component-mode? positive-component-id
        positive-component-members positive-component-rules positive-component-predecessors)
(defstruct positive-component (id members rules predecessors))

;;; Primitive operations own the cache lock; complete immutable planning stays
;;; outside it. Failed construction publishes nothing. Source/frame state never
;;; enters this cache. Preserve the existing weak Analysis identity key.
(def +positive-components-cache+
  (make-hash-table-eq weak-keys: #t lock: (make-mutex 'ascent-positive-components)))
;; : (-> ImmutableAnalysis ImmutableComponents)
(def (gerbil-ascent-positive-components analysis)
  (or (hash-get +positive-components-cache+ analysis)
      (let (fresh (gerbil-ascent-compile-positive-components analysis))
        (hash-put! +positive-components-cache+ analysis fresh)
        fresh)))

;; : (-> Boolean PositiveInteger (Maybe Cancellation) ImmutableAnalysis ProgramSchema Boolean)
(def (gerbil-ascent-component-mode? session? workers canceled? analysis schema)
  (and (not session?) (or (> workers 1) canceled?)
       (andmap (lambda (rules) (andmap (lambda (rule) (vector-ref rule 5)) rules))
               (vector->list (vector-ref analysis 5)))
       (andmap gerbil-ascent-canonical-set-storage-provider? (vector->list (vector-ref schema 9)))
       (andmap gerbil-ascent-canonical-hash-index-provider? (vector->list (vector-ref schema 5)))
       (andmap not (vector->list (vector-ref schema 7)))
       (andmap not (vector->list (vector-ref schema 3)))))



;; gerbil-ascent-compile-positive-components
;; : (-> Analysis [PositiveComponent])
;; | doc m%
;;     Group ordered compiled outputs by dense relation SCC in one head pass.
;;     Reuse the admitted body and slot count; only projected output headers are
;;     new. Component IDs, predecessor order and reverse source-rule order retain
;;     the coordinator's existing scheduling semantics.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-positive-components analysis)
;;     ;; => immutable SCC metadata, without variable frames or row state
;;     ```
;;   %
(def (gerbil-ascent-compile-positive-components analysis)
  (let* ((successors (vector-ref analysis 6))
         (count (vector-length successors))
         (groups (gerbil-ascent-graph-components successors))
         (membership (make-vector count #f))
         (components (map (lambda (id members) (make-positive-component id members [] []))
                          (iota (length groups)) groups)))
    (for-each
     (lambda (component)
       (for-each (lambda (relation) (vector-set! membership relation component))
                 (positive-component-members component))) components)
    (for-each
     (lambda (rules)
       (for-each
        (lambda (rule)
          (let ((full (vector-ref rule 5)) (outputs-by-component (make-hash-table-eq)))
            (unless full (error "unsupported ASCENT positive SCC rule"))
            (for-each
             (lambda (output)
               (let (component (vector-ref membership (vector-ref (vector-ref output 0) 0)))
                 (hash-update! outputs-by-component component (cut cons output <>) [])))
             (vector-ref full 0))
            (let (single? (= (hash-length outputs-by-component) 1))
              (hash-for-each
               (lambda (component outputs)
                 (let (plan (if single? full
                              (vector (reverse! outputs) (vector-ref full 1) (vector-ref full 2))))
                   (positive-component-rules-set! component
                     (cons (vector plan (vector-ref rule 2)) (positive-component-rules component)))))
               outputs-by-component)))) rules))
     (vector->list (vector-ref analysis 5)))
    (for-each
     (lambda (source)
       (for-each
        (lambda (target)
          (let ((from (vector-ref membership source)) (to (vector-ref membership target)))
            (unless (or (eq? from to)
                        (memv (positive-component-id from) (positive-component-predecessors to)))
              (positive-component-predecessors-set! to
                (cons (positive-component-id from) (positive-component-predecessors to))))))
        (vector-ref successors source))) (iota count))
    components))
