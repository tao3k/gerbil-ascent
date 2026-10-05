;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Only the coordinator owns global unique-row charging, ready admission and
;;; completed frontiers. Planning and one worker's local closure have owners.
(import :gerbil-ascent/program/component-plan
        (only-in "reference-worker.ss" make-component-snapshot gerbil-ascent-run-positive-component!)
        (only-in :gerbil-ascent/program/actor-round gerbil-ascent-run-actor-round!))
(export gerbil-ascent-positive-components gerbil-ascent-compile-positive-components
        gerbil-ascent-component-mode? gerbil-ascent-run-positive-components!
        positive-component-id positive-component-members positive-component-rules positive-component-predecessors)

;; gerbil-ascent-run-positive-components!
;; : (-> Analysis ProgramSchema Rows Workers Merge Canceled Void)
;; | doc m%
;;     Coordinate projected SCCs against a private tentative frontier. Each ready
;;     assignment receives its own root/size vectors, with persistent row roots.
;;     Only the owner charges global unique rows and admits successors after
;;     terminal join and all predecessor merge credits. Worker state is never
;;     shared with that owner or with another assignment.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-run-positive-components! analysis schema initial 2 merge canceled?)
;;     ;; => closes required SCCs or drains workers before raising failure
;;     ```
;;   %
(def (gerbil-ascent-run-positive-components! analysis schema initial workers merge canceled?)
  (let* ((components (gerbil-ascent-positive-components analysis))
         (frontier (vector-copy initial))
         (sizes (vector-map length frontier))
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
       (let* ((id (positive-component-id component)) (snapshot (vector-ref snapshots id)))
         ;; Ready admission transfers the fresh vectors to exactly one worker.
         ;; The owner retains only this opaque reference and never reads or
         ;; mutates either vector after admission.
         (gerbil-ascent-run-positive-component! component schema snapshot emit! checkpoint!)))
     (lambda (atom row)
       (let* ((index (vector-ref atom 0)) (table (vector-ref known index)))
         (unless (hash-get table row)
           (merge atom row)
           (hash-put! table row #t)
           (vector-set! frontier index (cons row (vector-ref frontier index)))
           (vector-set! sizes index (+ 1 (vector-ref sizes index))))))
     canceled?
     (lambda (component)
       (and (andmap (lambda (id) (vector-ref done id)) (positive-component-predecessors component))
            (begin
              (vector-set! snapshots (positive-component-id component)
                (make-component-snapshot (vector-copy frontier) (vector-copy sizes))) #t)))
     (lambda (component) (vector-set! done (positive-component-id component) #t)))))
