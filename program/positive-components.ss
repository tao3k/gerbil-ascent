;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/core/dependency-graph gerbil-ascent-graph-components)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-compile-positive-plan gerbil-ascent-run-positive-plan!)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows)
        (only-in "actor-round.ss" gerbil-ascent-run-actor-round!))
(export gerbil-ascent-positive-components gerbil-ascent-run-positive-components!
        positive-component-id positive-component-members positive-component-rules positive-component-predecessors)
(defstruct positive-component (id members rules predecessors))

;;; Project each admitted head to its relation SCC. Canonical lowering retains
;;; the complete ordered body and fresh variable frame for every projection.
(def (gerbil-ascent-positive-components analysis)
  (let* ((successors (vector-ref analysis 6)) (count (vector-length successors))
         (groups (gerbil-ascent-graph-components successors))
         (membership (make-vector count #f))
         (components (list->vector
                      (map (lambda (id members) (make-positive-component id members [] []))
                           (iota (length groups)) groups))))
    (for-each (lambda (component)
                (for-each (lambda (relation) (vector-set! membership relation component))
                          (positive-component-members component))) (vector->list components))
    (for-each
     (lambda (rules)
       (for-each
        (lambda (rule)
          (for-each
           (lambda (component)
             (let (heads (filter (lambda (head) (eq? (vector-ref membership (vector-ref head 0)) component)) (vector-ref rule 0)))
               (unless (null? heads)
                 (let (plan (gerbil-ascent-compile-positive-plan heads (vector-ref rule 1)))
                   (unless plan (error "unsupported ASCENT positive SCC rule"))
                   (positive-component-rules-set! component
                     (cons (vector plan (vector-ref rule 2)) (positive-component-rules component)))))))
           (vector->list components))) rules)) (vector->list (vector-ref analysis 5)))
    (for-each
     (lambda (source)
       (for-each
        (lambda (target)
          (let ((from (vector-ref membership source)) (to (vector-ref membership target)))
            (unless (or (eq? from to) (memv (positive-component-id from) (positive-component-predecessors to)))
              (positive-component-predecessors-set! to (cons (positive-component-id from) (positive-component-predecessors to))))))
        (vector-ref successors source))) (iota count))
    (vector->list components)))

;;; Global tentative frontier and unique-row charging belong to the coordinator.
;;; A successor is ready only after terminal join AND all predecessor batches
;;; have received merge credit. Other independent SCCs need not close first.
(def (gerbil-ascent-run-positive-components! analysis schema initial workers merge canceled?)
  (let* ((components (gerbil-ascent-positive-components analysis))
         (frontier (vector-copy initial)) (count (vector-length frontier))
         (known (vector-map (lambda (rows)
                              (let (table (make-hash-table))
                                (for-each (lambda (row) (hash-put! table row #t)) rows) table)) frontier))
         (done (make-vector (length components) #f))
         (snapshots (make-vector (length components) #f)))
    (for-each (lambda (component)
                (when (null? (positive-component-rules component))
                  (vector-set! done (positive-component-id component) #t))) components)
    (gerbil-ascent-run-actor-round!
     (vector analysis initial 'components)
     (filter (lambda (component) (pair? (positive-component-rules component))) components) workers
     (lambda (component emit! checkpoint!)
       ;; Ready admission captured roots on the owner before dispatch. The
       ;; worker never copies a vector concurrently mutated by another owner.
       (let* ((all (vector-copy (vector-ref snapshots (positive-component-id component)))) (delta (make-vector count []))
              (all-size (vector-map length all)) (delta-size (make-vector count 0))
              (all-version (make-vector count 0)) (delta-version (make-vector count 0))
              (indexes (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version (vector-ref schema 5)))
              (rows-access (row-indexes-rows indexes))
              (seen (vector-map (lambda (rows)
                                 (let (table (make-hash-table))
                                   (for-each (lambda (row) (hash-put! table row #t)) rows) table)) all))
              (rules (map (lambda (rule) (vector (vector-ref rule 0) (vector-ref rule 1)
                                              (make-vector (vector-ref (vector-ref rule 0) 2) #f)))
                          (positive-component-rules component))))
         (let rounds ((first? #t))
           (let ((pending (make-vector count [])) (new? #f))
             (def (candidate! atom row)
               (let* ((index (vector-ref atom 0)) (table (vector-ref seen index)))
                 (unless (hash-get table row)
                   (hash-put! table row #t)
                   (vector-set! pending index (cons row (vector-ref pending index)))
                   (set! new? #t)
                   (emit! atom row))))
             (for-each
              (lambda (rule)
                (let ((plan (vector-ref rule 0)) (pivots (vector-ref rule 1)) (frame (vector-ref rule 2)))
                  (if first?
                    (gerbil-ascent-run-positive-plan! plan frame -1 rows-access candidate! checkpoint!)
                    (for-each (lambda (pivot)
                                (gerbil-ascent-run-positive-plan! plan frame pivot rows-access candidate! checkpoint!)) pivots)))) rules)
             (for-each
              (lambda (index)
                (let (batch (vector-ref pending index))
                  (unless (null? batch)
                    (vector-set! all index (append batch (vector-ref all index)))
                    (vector-set! all-size index (+ (vector-ref all-size index) (length batch)))
                    (vector-set! all-version index (+ 1 (vector-ref all-version index))))
                  (vector-set! delta index batch)
                  (vector-set! delta-size index (length batch))
                  (vector-set! delta-version index (+ 1 (vector-ref delta-version index)))))
              (positive-component-members component))
             (when new? (rounds #f))))))
     (lambda (atom row)
       (let* ((index (vector-ref atom 0)) (table (vector-ref known index)))
         (unless (hash-get table row)
           (merge atom row)
           (hash-put! table row #t)
           (vector-set! frontier index (cons row (vector-ref frontier index))))))
     canceled?
     (lambda (component)
       (and (andmap (lambda (id) (vector-ref done id)) (positive-component-predecessors component))
            (begin (vector-set! snapshots (positive-component-id component) (vector-copy frontier)) #t)))
     (lambda (component) (vector-set! done (positive-component-id component) #t)))))
