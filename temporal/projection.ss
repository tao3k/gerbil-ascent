;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Invocation-owned graph projection; no snapshots or proof production here.
(import (only-in :gerbil-ascent/temporal/value position? valid-time?
                 time-lower time-upper temporal-window-verdict)
        (only-in :gerbil-ascent/temporal/graph temporal-cut-cyclic?))
(export project-temporal-cut temporal-cut-projection-edges
        temporal-cut-projection-frontier temporal-cut-projection-rejection)
(defstruct temporal-cut-projection (edges frontier rejection))

;;; Facts belong to one detached projection. Canonical lists still own
;;; iteration order; these records never escape into a value or receipt.
(defstruct projection-node (data member? eligible? outgoing discovery window))

(def (projection-index events members)
  (let (table (make-hash-table-eq size: (length events)))
    (for-each (lambda (event)
      ;; Preserve assq's first occurrence for supplied projections as well.
      (unless (hash-get table (car event))
        (hash-put! table (car event) (make-projection-node event #f #f [] #f #f)))) events)
    (for-each (lambda (id)
      (let (entry (hash-get table id))
        (if entry (projection-node-member?-set! entry #t)
            (hash-put! table id (make-projection-node #f #t #f [] #f #f))))) members)
    table))
(def (cut-member? index id)
  (let (entry (hash-get index id)) (and entry (projection-node-member? entry))))
(def (indexed-event index id)
  (let (entry (hash-get index id)) (and entry (projection-node-data entry))))
(def (eligible-member? index id)
  (let (entry (hash-get index id)) (and entry (projection-node-eligible? entry))))
(def (checked-window-verdict data start end)
  ;; Canonical exact points admit a direct comparison. Other admitted bounds
  ;; retain the same three-valued interval formula as the public wrapper.
  (if (exact-integer? data)
    (if (and (<= start data) (< data end)) 'true 'false)
    (let ((lower (time-lower data)) (upper (time-upper data)))
      (cond ((or (>= lower end) (and upper (< upper start))) 'false)
            ((and upper (<= start lower) (< upper end)) 'true)
            (else 'unknown)))))
(def (select-eligible! index events as-of start end)
  (for-each (lambda (event)
    (let (node (hash-ref index (car event)))
      (when (and (projection-node-member? node) (<= (caddr event) as-of)
                 (eq? (or (and (eq? event (projection-node-data node))
                               (projection-node-window node))
                          (temporal-window-verdict (cadr event) start end)) 'true))
        (projection-node-eligible?-set! node #t)))) events))

;; Index stable edge ordinals once. Layer discovery may visit parents in any
;; order; minimum incoming ordinal recovers the original first-edge witness.
;; Discovery entries are #t for settled vertices or an edge for this layer.
(def (indexed-horizon-frontier edges root horizon index)
  (let rank-edges ((rest edges) (rank 0))
    (unless (null? rest)
      (let* ((edge (car rest)) (from (hash-ref index (car edge))))
        (projection-node-outgoing-set! from (cons (cons rank (cadr edge)) (projection-node-outgoing from)))
        (rank-edges (cdr rest) (+ rank 1)))))
  ;; Restore original edge order inside each source bucket. A single-parent
  ;; layer can then emit reverse first-discovery order directly.
  (hash-for-each (lambda (_ node)
    (projection-node-outgoing-set! node (reverse (projection-node-outgoing node)))) index)
  (let (root-node (hash-get index root))
    (and root-node
      (begin
        (projection-node-discovery-set! root-node #t)
        (let loop ((front (list root)) (depth 0))
          (let (ids [])
            (for-each (lambda (from)
              (for-each (lambda (edge)
                (let* ((target (cdr edge)) (node (hash-ref index target))
                       (first (projection-node-discovery node)))
                  (cond ((not first)
                         (projection-node-discovery-set! node edge)
                         (set! ids (cons target ids)))
                        ((and (pair? first) (< (car edge) (car first)))
                         (projection-node-discovery-set! node edge)))))
                (projection-node-outgoing (hash-ref index from)))) front)
            (let (next (if (or (null? ids) (null? (cdr ids)) (null? (cdr front))) ids
                        (map cdr (list-sort (lambda (a b) (> (car a) (car b)))
                          (map (lambda (id) (projection-node-discovery (hash-ref index id))) ids)))))
              (cond ((null? next) #f)
                    ((>= depth horizon) next)
                    (else (for-each (lambda (id)
                            (projection-node-discovery-set! (hash-ref index id) #t)) next)
                          (loop next (+ depth 1)))))))))))

;; Zero horizon admits one source-ordered edge pass without building adjacency.
(def (horizon-frontier edges root horizon index)
  (if (zero? horizon)
    (let ((root-node (hash-get index root)) (next []))
      (when root-node (projection-node-discovery-set! root-node #t))
      (for-each (lambda (edge)
        (when (eq? (car edge) root)
          (let (node (hash-ref index (cadr edge)))
            (unless (projection-node-discovery node)
              (projection-node-discovery-set! node #t)
              (set! next (cons (cadr edge) next)))))) edges)
      (and (pair? next) next))
    (indexed-horizon-frontier edges root horizon index)))

;;; Project detached coordinates once. Canonical lists own diagnostic order;
;;; supplied callback values retain the original evaluation schedule.
;; : (-> LensData SourceData EventId TemporalCutProjection)
(def (project-temporal-cut l s root)
  (with (([generation clock start end as-of cut members horizon closed?] l)
         ([_ source-generation source-clock events parents] s))
    (let* ((index (projection-index events members))
         (canonical-window? (and (position? start) (position? end) (< start end)
                                 (andmap (lambda (event) (valid-time? (cadr event))) events)))
         (cut-edges (filter (lambda (edge) (cut-member? index (cadr edge))) parents))
         (frontier []) (rejection #f))
    (def (open! code detail) (set! frontier (cons (list code detail) frontier)))
    (def (reject! code) (unless rejection (set! rejection code)))
    (unless (= generation source-generation) (reject! 'generation-mismatch))
    (unless (eq? clock source-clock) (reject! 'clock-mismatch))
    (unless closed? (open! 'open-cut cut))
    (unless (cut-member? index root) (reject! 'root-outside-cut))
    (for-each
     (lambda (id)
       (let* ((node (hash-ref index id)) (event (projection-node-data node)))
         (cond ((not event) (open! 'missing-event id))
               ((> (caddr event) as-of) (open! 'knowledge-unavailable id))
               (else
                (let (verdict (if canonical-window?
                               (checked-window-verdict (cadr event) start end)
                               (temporal-window-verdict (cadr event) start end)))
                  ;; Only inert canonical bounds are stable across calls.
                  ;; Callback-backed supplied values keep their original calls.
                  (when canonical-window? (projection-node-window-set! node verdict))
                  (when (eq? verdict 'unknown) (open! 'unknown-valid-time id)))))))
     members)
    (for-each
     (lambda (edge)
       (unless (cut-member? index (car edge)) (open! 'missing-parent edge))
       (let ((from (indexed-event index (car edge))) (to (indexed-event index (cadr edge))))
         (when (and from to)
           (let ((lower-from (time-lower (cadr from)))
                 (upper-from (time-upper (cadr from)))
                 (lower-to (time-lower (cadr to)))
                 (upper-to (time-upper (cadr to))))
             (cond ((and upper-to (> lower-from upper-to))
                    (reject! 'order-violation))
                   ((not (and upper-from (<= upper-from lower-to)))
                    (open! 'unknown-parent-order edge))))))) cut-edges)
    ;; Parent closure and cycles are checked even outside the valid window.
    (when (temporal-cut-cyclic? cut-edges) (reject! 'cyclic-cut))
    (select-eligible! index events as-of start end)
    (let* ((edges (filter (lambda (edge)
                    (and (eligible-member? index (car edge))
                         (eligible-member? index (cadr edge)))) cut-edges))
           (boundary (horizon-frontier edges root horizon index)))
      ;; An open frontier is explicit; no absence claim or complete receipt.
      (when boundary (open! 'horizon-frontier boundary))
      (make-temporal-cut-projection edges (reverse frontier) rejection)))))
