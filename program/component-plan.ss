;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Immutable SCC execution metadata. Construction owns temporary grouping
;;; tables; returned components share admitted slot actions, never worker state.
(import (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-pure-positive-plan?
                 gerbil-ascent-positive-plan-with-outputs)
        (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?))
(export gerbil-ascent-positive-components gerbil-ascent-compile-positive-components
        gerbil-ascent-component-mode? positive-component-id
        positive-component-members positive-component-rules positive-component-predecessors)
(defstruct positive-component (id members rules predecessors))

;;; Publication owns the rule wrapper; full survivors retain admitted identity.
(def (publish-component-rule! component plan pivots)
  (positive-component-rules-set! component
    (cons (vector plan pivots) (positive-component-rules component))))

(def (project-component-rule! rule membership)
  (let ((full (vector-ref rule 5)) (pivots (vector-ref rule 2)))
    (unless (gerbil-ascent-pure-positive-plan? full)
      (error "unsupported ASCENT positive SCC rule"))
    (def (owner output)
      (vector-ref membership (vector-ref (vector-ref output 0) 0)))
    (match (vector-ref full 0)
      ([] (void))
      ([first . rest]
       (let (component (owner first))
         (if (andmap (lambda (output) (eq? component (owner output))) rest)
           (publish-component-rule! component full pivots)
           (let (grouped (make-hash-table-eq))
             (for-each (lambda (output)
                         (hash-update! grouped (owner output) (cut cons output <>) []))
                       (vector-ref full 0))
             (hash-for-each
              (lambda (component outputs)
                (publish-component-rule! component
                  (gerbil-ascent-positive-plan-with-outputs full (reverse! outputs)) pivots))
              grouped))))))))

;;; Keep the first predecessor inline. Promote to construction-owned membership
;;; only on a second distinct predecessor; returned metadata retains no tables.
(def (bitmap-first-visit! bitmap id)
  (let* ((byte (quotient id 8)) (mask (arithmetic-shift 1 (modulo id 8)))
         (previous (u8vector-ref bitmap byte)))
    (and (zero? (bitwise-and previous mask))
         (begin (u8vector-set! bitmap byte (bitwise-ior previous mask)) #t))))

;;; A hash entry costs more than a bit. Promote only when observed occupancy
;;; pays for the entire dense bitmap, so sparse graphs retain sparse storage.
(def (predecessor-first-visit! seen target id first)
  (let (members (vector-ref seen target))
    (unless members
      (set! members (make-hash-table-eqv))
      (hash-put! members first #t)
      (vector-set! seen target members))
    (cond
     ((u8vector? members) (bitmap-first-visit! members id))
     ((hash-get members id) #f)
     (else
      (hash-put! members id #t)
      (when (>= (hash-length members) (max 32 (quotient (vector-length seen) 128)))
        (let (bitmap (make-u8vector (quotient (+ (vector-length seen) 7) 8) 0))
          (hash-for-each (lambda (key _) (bitmap-first-visit! bitmap key)) members)
          (vector-set! seen target bitmap)))
      #t))))

(def (register-component-predecessor! from to seen)
  (unless (eq? from to)
    (let ((id (positive-component-id from))
          (previous (positive-component-predecessors to)))
      (unless (and (pair? previous) (eqv? id (car previous)))
        (when (or (null? previous)
                  (predecessor-first-visit! seen (positive-component-id to) id (car previous)))
          (positive-component-predecessors-set! to (cons id previous)))))))

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
       (andmap (lambda (rules) (andmap (lambda (rule) (gerbil-ascent-pure-positive-plan? (vector-ref rule 5))) rules))
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
                          (iota (length groups)) groups))
         (predecessors-seen (make-vector (length groups) #f)))
    (for-each
     (lambda (component)
       (for-each (lambda (relation) (vector-set! membership relation component))
                 (positive-component-members component))) components)
    (for-each
     (lambda (rules)
       (for-each
        (cut project-component-rule! <> membership) rules))
     (vector->list (vector-ref analysis 5)))
    (for-each
     (lambda (source)
       (for-each
        (lambda (target)
          (register-component-predecessor! (vector-ref membership source)
                                           (vector-ref membership target) predecessors-seen))
        (vector-ref successors source))) (iota count))
    components))
