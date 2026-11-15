;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Only the coordinator owns global unique-row charging, ready admission and
;;; completed frontiers. Planning and one worker's local closure have owners.
(import "component-plan.ss"
        (only-in :gerbil-ascent/core/execution-policy gerbil-ascent-component-ready)
        (only-in :std/iter for/fold in-list)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance!)
        (only-in "component-worker.ss" gerbil-ascent-component-snapshot gerbil-ascent-run-positive-component!)
        (only-in "actor-round.ss" gerbil-ascent-run-actor-round!))
(export gerbil-ascent-positive-components gerbil-ascent-compile-positive-components
        gerbil-ascent-component-mode? gerbil-ascent-run-positive-components!
        positive-component-id positive-component-members positive-component-rules positive-component-predecessors)

;;; A Session owns one physical index per source slot. Only its joined,
;;; single-worker evaluator lends or mutates it. Results own rows, not indexes.
(defstruct actor-source-index (rows sizes versions indexes) final: #t)

;; Collect just the new prefix, in chronological order for native extension.
;; The exact owned suffix must match; sizes and row equality alone cannot
;; certify a replacement or a return to an earlier admitted source.
;; : (forall (r) (-> [r] Integer [r] (Maybe [r])))
;; : (-> Rows SignedRowDifference Rows (Maybe ChronologicalRows))
(def (actor-source-additions rows count prior)
  (let scan ((rest rows) (left count) (chronological []))
    (if (<= left 0)
      (and (zero? left) (eq? rest prior) chronological)
      (scan (cdr rest) (- left 1) (cons (car rest) chronological)))))

;; : (forall (i r p) (-> (Vector (Maybe i)) Natural [r] Natural p i))
;; : (-> RetainedSourceIndexes RelationOrdinal Rows Natural IndexProvider ActorSourceIndex)
(def (prepare-actor-source-index! retained position rows size provider)
  (let (current (vector-ref retained position))
    (if (and current (eq? rows (vector-ref (actor-source-index-rows current) 0)))
      current
      (let (added (and current
                       (actor-source-additions rows
                         (- size (vector-ref (actor-source-index-sizes current) 0))
                         (vector-ref (actor-source-index-rows current) 0))))
        ;; Revoke before mutating. A partially extended index cannot survive
        ;; an exception, and replacement releases the obsolete index first.
        (vector-set! retained position #f)
        (let (next
              (if added
                (using (entry current :- actor-source-index)
                  ((row-indexes-advance! entry.indexes) 0 added)
                  (vector-set! entry.rows 0 rows)
                  (vector-set! entry.sizes 0 size)
                  (vector-set! entry.versions 0 (+ 1 (vector-ref entry.versions 0)))
                  entry)
                (let ((total (vector rows)) (sizes (vector size)) (version (vector 0)))
                  (make-actor-source-index total sizes version
                    (gerbil-ascent-make-row-indexes total (vector []) sizes
                      '#(0) version '#(0) (vector provider))))))
          (vector-set! retained position next)
          next)))))

;; The per-run readers resolve each slot once. Each probe then uses the
;; standard index's descriptor and version caches.
;; : (forall (i r p a f t) (-> (Vector (Maybe i)) (Vector [r]) (Vector Natural) (Vector p) (-> a f t [r])))
;; : (-> RetainedSourceIndexes RowsVector Sizes IndexProviders (-> Atom Frame Terms Rows))
(def (actor-source-reader retained initial sizes providers)
  (let (readers (make-vector (vector-length initial) #f))
    (lambda (atom frame terms)
      (let* ((position (vector-ref atom 0)) (size (vector-ref sizes position)))
        (if (< size 32)
          (begin (vector-set! retained position #f) (vector-ref initial position))
          (let (lookup
                (or (vector-ref readers position)
                    (let* ((entry (prepare-actor-source-index! retained position
                                    (vector-ref initial position) size
                                    (vector-ref providers position)))
                           (read (row-indexes-rows (actor-source-index-indexes entry))))
                      (vector-set! readers position read)
                      read)))
            (lookup atom frame #f terms #f #f 0)))))))

;; gerbil-ascent-run-positive-components!
;; : (forall (a s r m c i) (-> a s r PositiveInteger m c Boolean (Maybe i) Void))
;; : (-> Analysis ProgramSchema Rows Workers Merge Canceled Boolean (Maybe SourceIndexes) Void)
;; | doc m%
;;     Coordinate projected SCCs against a private tentative frontier. Each ready
;;     assignment receives its own root/size vectors, with persistent row roots.
;;     Only the owner charges global unique rows and admits successors after
;;     terminal task completion and all predecessor merge credits. A single
;;     worker may retain keyed reads of owned scalar source-only relations for
;;     the whole run. A Session may supply its private versioned source indexes.
;;     Each assignment still owns its writable relation indexes.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-run-positive-components! analysis schema initial 2 merge canceled?)
;;     ;; => closes required SCCs or drains workers before raising failure
;;     ```
;;   %
(def (gerbil-ascent-run-positive-components! analysis schema initial workers merge canceled?
                                               (scalar-source-owner? #f) (retained-source-indexes #f))
  (let* ((components (gerbil-ascent-positive-components analysis))
         (frontier (vector-copy initial))
         (sizes (vector-map length frontier))
         ;; Only rule-owning SCC members can receive candidates. Source-only
         ;; relations keep their persistent roots without another membership table.
         (known (make-vector (vector-length initial) #f))
         (by-id (list->vector components))
         (remaining (make-vector (length components) 0))
         (snapshots (make-vector (length components) #f))
         (assigned (filter (lambda (component) (pair? (positive-component-rules component))) components))
         (source-indexes
          (and scalar-source-owner? (= workers 1) (pair? assigned) (pair? (cdr assigned))
               (if retained-source-indexes
                 (actor-source-reader retained-source-indexes initial sizes (vector-ref schema 5))
                 (let* ((width (vector-length initial)) (zeros (make-vector width 0))
                        (lookup (row-indexes-rows
                                 (gerbil-ascent-make-row-indexes initial (make-vector width []) sizes zeros
                                   zeros zeros (vector-ref schema 5)))))
                   (lambda (atom frame terms) (lookup atom frame #f terms)))))))

    ;; The envelope admits one reader at a time. Source-only slots have no
    ;; writer, so their initial total cut stays exact until the pool joins.
    (def (read-source atom frame terms)
      (and (not (vector-ref known (vector-ref atom 0)))
           (source-indexes atom frame terms)))
    (for-each (lambda (component)
                (if (null? (positive-component-rules component))
                  (void)
                  (for-each
                   (lambda (index)
                     (let (table (make-hash-table))
                       (for-each (lambda (row) (hash-put! table row #t)) (vector-ref frontier index))
                       (vector-set! known index table)))
                   (positive-component-members component)))
                ;; Source-only predecessors are complete before task admission.
                ;; Only the owner updates dependency counts after terminal merges.
                (vector-set! remaining (positive-component-id component)
                  (for/fold (blocked 0) (id (in-list (positive-component-predecessors component)))
                    (+ blocked (if (pair? (positive-component-rules (vector-ref by-id id))) 1 0))))) components)
    (gerbil-ascent-run-actor-round!
     (vector analysis initial 'components)
     assigned workers
     (lambda (component emit! checkpoint!)
       (let* ((id (positive-component-id component)) (snapshot (vector-ref snapshots id)))
         ;; Ready admission transfers the fresh vectors to exactly one worker.
         ;; The owner retains only this opaque reference and never reads or
         ;; mutates either vector after admission.
         (gerbil-ascent-run-positive-component! component schema snapshot emit! checkpoint!
           (and source-indexes read-source))))
     (lambda (atom row)
       (let* ((index (vector-ref atom 0)) (table (vector-ref known index)))
         (unless (hash-get table row)
           (merge atom row)
           (hash-put! table row #t)
           (vector-set! frontier index (cons row (vector-ref frontier index)))
           (vector-set! sizes index (+ 1 (vector-ref sizes index))))))
     canceled?
     (lambda (component)
       (and (gerbil-ascent-component-ready (vector-ref remaining (positive-component-id component)))
            (begin
              (vector-set! snapshots (positive-component-id component)
                (gerbil-ascent-component-snapshot component frontier sizes)) #t)))
     (lambda (component)
       (let (id (positive-component-id component))
         ;; Completion follows all owner merges; the snapshot is no longer
         ;; needed for dependency admission or round cleanup.
         (vector-set! snapshots id #f)
         (for-each (lambda (successor)
                     (vector-set! remaining successor (- (vector-ref remaining successor) 1)))
                   (positive-component-successors component)))))))
