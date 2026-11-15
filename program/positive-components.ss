;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Only the coordinator owns global unique-row charging, ready admission and
;;; completed frontiers. Planning and one worker's local closure have owners.
(import "component-plan.ss"
        (only-in :gerbil-ascent/core/execution-policy gerbil-ascent-component-ready)
        (only-in :std/iter for/fold in-list)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows)
        (only-in "component-worker.ss" gerbil-ascent-component-snapshot gerbil-ascent-run-positive-component!)
        (only-in "actor-round.ss" gerbil-ascent-run-actor-round!))
(export gerbil-ascent-positive-components gerbil-ascent-compile-positive-components
        gerbil-ascent-component-mode? gerbil-ascent-run-positive-components!
        positive-component-id positive-component-members positive-component-rules positive-component-predecessors)

;; gerbil-ascent-run-positive-components!
;; : (-> Analysis ProgramSchema Rows Workers Merge Canceled Boolean Void)
;; | doc m%
;;     Coordinate projected SCCs against a private tentative frontier. Each ready
;;     assignment receives its own root/size vectors, with persistent row roots.
;;     Only the owner charges global unique rows and admits successors after
;;     terminal task completion and all predecessor merge credits. A single
;;     worker may retain keyed reads of owned scalar source-only relations for
;;     the whole run. Each assignment still owns its writable relation indexes.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-run-positive-components! analysis schema initial 2 merge canceled?)
;;     ;; => closes required SCCs or drains workers before raising failure
;;     ```
;;   %
(def (gerbil-ascent-run-positive-components! analysis schema initial workers merge canceled?
                                               (scalar-source-owner? #f))
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
               (let* ((width (vector-length initial)) (zeros (make-vector width 0)))
                 (row-indexes-rows
                  (gerbil-ascent-make-row-indexes initial (make-vector width []) sizes zeros
                    zeros zeros (vector-ref schema 5)))))))
    ;; The envelope admits one reader at a time. Source-only slots have no
    ;; writer, so their initial total cut stays exact until the pool joins.
    (def (read-source atom frame terms)
      (and (not (vector-ref known (vector-ref atom 0)))
           (source-indexes atom frame #f terms)))
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
