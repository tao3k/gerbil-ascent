;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private union-find SCCs and reachability between component roots.
;;; Concrete frontier rows are returned, never retained in this provider.
(export gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension
        gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-snapshot
        gerbil-ascent-trrel-uf-view-count gerbil-ascent-trrel-uf-view-for-each
        gerbil-ascent-trrel-uf-view-lookup gerbil-ascent-trrel-uf-observation)
(defstruct uf-node (parent members size reach))
(defstruct uf-group (nodes roots))
;;; Private frozen descriptors contain member list roots, never mutable nodes.
;;; Merge replaces member roots without mutating their list spines. Field values
;;; retain the existing borrowed identity contract; this is not a deep freeze.
(defstruct uf-rectangle (prefix from to))
(defstruct uf-view (rectangles count))

;; : (-> UfView Natural)
(def (gerbil-ascent-trrel-uf-view-count view) (uf-view-count view))

;; : (-> UfView (-> Row Any) Void)
(def (gerbil-ascent-trrel-uf-view-for-each view consume)
  (for-each
   (lambda (rectangle)
     (for-each (lambda (from)
       (for-each (lambda (to)
         (consume (append (uf-rectangle-prefix rectangle) (list from to))))
         (uf-rectangle-to rectangle)))
       (uf-rectangle-from rectangle)))
   (uf-view-rectangles view)))

;;; Key filtering precedes Cartesian enumeration. Each invocation owns its
;;; returned row spines; no cursor or materialized tuple cache lives in the view.
;; : (-> UfView (List Natural) Row Rows)
(def (gerbil-ascent-trrel-uf-view-lookup view columns key)
  (unless (and (list? columns) (list? key) (= (length columns) (length key))
               (andmap (lambda (column) (and (exact-integer? column) (>= column 0))) columns))
    (error "invalid ASCENT UF view key"))
  (let (found [])
    (for-each
     (lambda (rectangle)
       (let* ((prefix (uf-rectangle-prefix rectangle)) (offset (length prefix)))
         (unless (andmap (lambda (column) (< column (+ offset 2))) columns)
           (error "invalid ASCENT UF view column"))
         (def (matches? column value)
           (let loop ((remaining columns) (values key))
             (or (null? remaining)
                 (and (or (not (= (car remaining) column)) (equal? (car values) value))
                      (loop (cdr remaining) (cdr values))))))
         (when (or (= offset 0) (matches? 0 (car prefix)))
           (for-each (lambda (from)
             (when (matches? offset from)
               (for-each (lambda (to)
                 (when (matches? (+ offset 1) to)
                   (set! found (cons (append prefix (list from to)) found))))
                 (uf-rectangle-to rectangle))))
             (uf-rectangle-from rectangle)))))
     (uf-view-rectangles view))
    (reverse found)))

;;; A total snapshot enumerates each reachable ordered component rectangle once.
;; : (-> UfState UfView)
(def (gerbil-ascent-trrel-uf-snapshot groups)
  (let ((rectangles []) (count 0))
    (hash-for-each (lambda (key group)
      (let (prefix (if (= (car key) 3) (list (cadr key)) []))
        (for-each (lambda (from)
          (for-each (lambda (to)
            (when (reachable? from to)
              (set! rectangles (cons (make-uf-rectangle prefix
                                      (uf-node-members from) (uf-node-members to)) rectangles))
              (set! count (+ count (* (uf-node-size from) (uf-node-size to))))))
            (uf-group-roots group)))
          (uf-group-roots group)))) groups)
    (make-uf-view (reverse rectangles) count)))
(def (gerbil-ascent-trrel-uf-state) (make-hash-table))
;; Preflight reads parent links without compression, preserving rejected state.
(def (root node)
  (if (uf-node-parent node) (root (uf-node-parent node)) node))
(def (reachable? from to)
  (or (eq? from to) (hash-get (uf-node-reach from) to)))
(def (fresh node) (make-uf-node #f (list node) 1 (make-hash-table-eq)))
;; Complete closure already gives the winner every outgoing cycle edge.
;; Keep its owned reach table; only absorbed keys need removal.
(def (merge-cycle! group roots cycle)
  (let* ((winner (foldl (lambda (n best)
                         (if (> (uf-node-size n) (uf-node-size best)) n best))
                       (car cycle) (cdr cycle)))
         (merged (uf-node-members winner))
         (size (uf-node-size winner)))
    (for-each (lambda (n)
      (unless (eq? n winner)
        (set! merged (append (uf-node-members n) merged))
        (set! size (+ size (uf-node-size n)))
        (set! (uf-node-parent n) winner)
        (set! (uf-node-members n) [])
        (set! (uf-node-size n) 0)
        (set! (uf-node-reach n) (make-hash-table-eq)))) cycle)
    (set! (uf-node-members winner) merged)
    (set! (uf-node-size winner) size)
    (set! roots (filter (lambda (n) (not (uf-node-parent n))) roots))
    (set! (uf-group-roots group) roots)
    ;; Canonical pre-merge keys plus complete closure mean any external
    ;; predecessor of an absorbed root already reaches the winner. Other DAG
    ;; keys need no rewrite. Iterate a stable list, never the changed table.
    (for-each (lambda (n)
      (if (and (eq? n winner)
               (or (null? (cdr roots))
                   (= (hash-length (uf-node-reach n)) (- (length cycle) 1))))
        ;; No external target: release the old backing array as well as keys.
        (set! (uf-node-reach n) (make-hash-table-eq))
        (when (or (eq? n winner) (hash-get (uf-node-reach n) winner))
          (for-each (lambda (target)
            (when (or (not (eq? target winner)) (eq? n winner))
              (hash-remove! (uf-node-reach n) target))) cycle)))) roots)))

(def (gerbil-ascent-trrel-uf-frontier-extension groups row budget)
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT trrel requires two or three columns" row)))
         (group-key (list width (if (= width 3) (car row) #f)))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair)) (right (cadr pair))
         (stored (hash-get groups group-key))
         (group (or stored (make-uf-group (make-hash-table) [])))
         (nodes (uf-group-nodes group))
         (left-node (hash-get nodes left)) (right-node (hash-get nodes right))
         (a (if left-node (root left-node) (fresh left)))
         (b (if (equal? left right) a (if right-node (root right-node) (fresh right))))
         (new (append (if left-node [] (list a))
                      (if (or right-node (eq? a b)) [] (list b))))
         (roots (append new (uf-group-roots group)))
         (preds (filter (lambda (p) (reachable? p a)) roots))
         (succs (filter (lambda (s) (reachable? b s)) roots))
         ;; Capture the intersection in root order before adjacency mutation.
         ;; Succ(b) membership is already represented by b's reach table.
         (cycle (and (not (eq? a b)) (reachable? b a)
                     (filter (lambda (p) (reachable? b p)) preds)))
         (changes []) (needed (length new)))
    ;; Count each missing component rectangle before rows or graph mutation.
    (for-each (lambda (p)
      (for-each (lambda (s)
        (unless (reachable? p s)
          (set! needed (+ needed (* (uf-node-size p) (uf-node-size s))))
          (set! changes (cons (cons p s) changes)))) succs)) preds)
    (when (> needed budget) (error "ASCENT trrel output fact budget exceeded"))
    (let* ((prefix (if (= width 3) (list (car row)) []))
           (rectangles
            (append (map (lambda (n) (make-uf-rectangle prefix
                                      (uf-node-members n) (uf-node-members n))) new)
                    (map (lambda (change) (make-uf-rectangle prefix
                                           (uf-node-members (car change))
                                           (uf-node-members (cdr change)))) changes)))
           (frontier (make-uf-view rectangles needed)))
    ;; No callback occurs between preflight and commit. Budget rejection has
    ;; not installed new nodes, rewritten parents or altered adjacency.
    (unless (null? new)
      (hash-put! groups group-key group)
      (unless left-node (hash-put! nodes left a))
      (unless right-node (hash-put! nodes right b))
      (set! (uf-group-roots group) roots))
    ;; If every root collapses, all changed arcs would immediately disappear.
    ;; Concrete member rectangles were frozen above; no external reach key survives.
    (unless (and cycle (= (length cycle) (length roots)))
      (for-each (lambda (change) (hash-put! (uf-node-reach (car change)) (cdr change) #t)) changes))
    ;; A new a->b edge makes precisely Pred(a) intersect Succ(b) cyclic.
    ;; Merge toward the largest component, bounding union parent depth.
    (when cycle
      (merge-cycle! group roots cycle))
    frontier)))

;;; The existing list-based engine consumes the same compressed frontier plan.
;;; This adapter preserves its concrete row order; engine view migration is separate.
;; : (-> UfState Rows Rows Row Natural Rows)
(def (gerbil-ascent-trrel-uf-extension groups _all _pending row budget)
  (let ((frontier (gerbil-ascent-trrel-uf-frontier-extension groups row budget))
        (rows []))
    (gerbil-ascent-trrel-uf-view-for-each frontier
      (lambda (row) (set! rows (cons row rows))))
    (reverse rows)))
;; Physical structure counts, not whole-engine memory or allocator receipts.
(def (gerbil-ascent-trrel-uf-observation groups)
  (let ((nodes 0) (components 0) (arcs 0))
    (hash-for-each (lambda (_ g)
      (set! nodes (+ nodes (hash-length (uf-group-nodes g))))
      (set! components (+ components (length (uf-group-roots g))))
      (for-each (lambda (n) (set! arcs (+ arcs (hash-length (uf-node-reach n)))))
                (uf-group-roots g))) groups)
    (vector nodes components arcs)))
