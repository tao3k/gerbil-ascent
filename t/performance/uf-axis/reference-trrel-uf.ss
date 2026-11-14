;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private union-find SCCs and reachability between component roots.
;;; Concrete frontier rows are returned, never retained in this provider.
(import :gerbil-ascent/core/relation-view)
(export gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-freeze
        gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension
        gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-snapshot
        gerbil-ascent-trrel-uf-view-count gerbil-ascent-trrel-uf-view-for-each
        gerbil-ascent-trrel-uf-view-lookup
        gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-validate
        gerbil-ascent-trrel-uf-replay-insert! gerbil-ascent-trrel-uf-count-insert!)
(defstruct uf-node (parent members size reach predecessors order))
(defstruct uf-group (nodes roots next-order indexed? population))
(defstruct uf-insertion (group-key group row left-node right-node a b) final: #t)
(defstruct frozen-members (rows count) final: #t)
;; : (-> UfState)
(def (gerbil-ascent-trrel-uf-state) (make-hash-table))
;; Preflight reads parent links without compression, preserving rejected state.
;; : (-> UfNode UfNode)
(def (root node)
  (if (uf-node-parent node) (root (uf-node-parent node)) node))
;; : (-> UfNode UfNode Boolean)
(def (reachable? from to)
  (or (eq? from to) (hash-get (uf-node-reach from) to)))
;; : (-> Value Natural Boolean UfNode)
(def (fresh node order indexed?)
  (make-uf-node #f (list node) 1 (make-hash-table-eq)
                (and indexed? (make-hash-table-eq)) order))
;; Match the legacy prepended root scan without touching unrelated components.
;; Sparse adjacency sorts only its keys; dense adjacency filters roots already
;; in writer order. Selection compares a sorting bound with the population.
;; : (-> UfNode RootTable [UfNode] Natural [UfNode])
(def (ordered-neighbors node table roots population)
  (let (degree (hash-length table))
    (cond
      ((zero? degree) (list node))
      ((>= (* degree (integer-length degree)) population)
       (filter (lambda (n) (or (eq? n node) (hash-get table n))) roots))
      (else (list-sort (lambda (a b) (> (uf-node-order a) (uf-node-order b)))
                      (cons node (hash-keys table)))))))
;; : (-> [UfNode] Void)
(def (rebuild-predecessors! roots)
  (for-each (lambda (n) (set! (uf-node-predecessors n) (make-hash-table-eq))) roots)
  (for-each (lambda (n)
    (hash-for-each (lambda (target _)
      (hash-put! (uf-node-predecessors target) n #t)) (uf-node-reach n))) roots))
;; Closure supplies every external edge to/from the surviving winner already.
;; Retire absorbed reverse keys before clearing any component's storage.
;; : (-> UfNode [UfNode] Void)
(def (retire-cycle-predecessors! winner cycle)
  (for-each (lambda (n)
    (unless (eq? n winner)
      (hash-for-each (lambda (target _)
        (hash-remove! (uf-node-predecessors target) n)) (uf-node-reach n)))
    (hash-remove! (uf-node-predecessors winner) n)) cycle))
;; Complete closure already gives the winner every outgoing cycle edge.
;; Keep its owned reach table; only absorbed keys need removal.
;; : (-> UfGroup [UfNode] [UfNode] Void)
(def (merge-cycle! group roots cycle)
  (let* ((winner (foldl (lambda (n best)
                         (if (> (uf-node-size n) (uf-node-size best)) n best))
                       (car cycle) (cdr cycle)))
         (merged (uf-node-members winner))
         (size (uf-node-size winner)))
    (when (uf-group-indexed? group)
      (if (= (length cycle) (uf-group-population group))
        ;; Every reverse key belongs to a retiring root. No external owner
        ;; survives to observe it; release the winner's whole backing table.
        (set! (uf-node-predecessors winner) (make-hash-table-eq))
        (retire-cycle-predecessors! winner cycle)))
    (for-each (lambda (n)
      (unless (eq? n winner)
        (set! merged (append (uf-node-members n) merged))
        (set! size (+ size (uf-node-size n)))
        (set! (uf-node-parent n) winner)
        (set! (uf-node-members n) [])
        (set! (uf-node-size n) 0)
        (set! (uf-node-reach n) (make-hash-table-eq))
        (set! (uf-node-predecessors n) #f))) cycle)
    (set! (uf-node-members winner) merged)
    (set! (uf-node-size winner) size)
    (set! roots (filter (lambda (n) (not (uf-node-parent n))) roots))
    (set! (uf-group-roots group) roots)
    (set! (uf-group-population group) (length roots))
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

;; : (forall (a) (-> UfState Row Natural (-> [Rectangle] Natural Natural a) a))
;; : (-> UfState Row Natural FrontierPublisher Publication)
(def (admit-insertion! groups row budget finish (rectangles? #t))
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT trrel requires two or three columns" row)))
         (group-key (list width (if (= width 3) (car row) #f)))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair)) (right (cadr pair))
         (stored (hash-get groups group-key))
         (group (or stored (make-uf-group (make-hash-table) [] 0 #f 0)))
         (nodes (uf-group-nodes group))
         (left-node (hash-get nodes left)) (right-node (hash-get nodes right))
         (a (if left-node (root left-node) (fresh left (+ 2 (uf-group-next-order group)) (uf-group-indexed? group))))
         (b (if (equal? left right) a (if right-node (root right-node) (fresh right (+ 1 (uf-group-next-order group)) (uf-group-indexed? group)))))
         (admitted? (and left-node right-node (reachable? a b))))
    (if admitted?
      (begin
        (when (< budget 0) (error "ASCENT trrel output fact budget exceeded"))
        (finish [] 0 0))
      (insert-components! groups (make-uf-insertion group-key group row left-node right-node a b) budget finish rectangles?))))

;; : (-> UfState Row Natural FrozenView)
(def (gerbil-ascent-trrel-uf-insert! groups row budget)
  (admit-insertion! groups row budget gerbil-ascent-rectangle-view))

;; gerbil-ascent-trrel-uf-replay-insert!
;; : (-> UfState Row Natural (-> Natural (Maybe RowWriter)) Void)
;; | doc m%
;;     Commit one whole UF injection before selecting its synchronous writer.
;;     Declined output still reconstructs state for later suffix injections.
;;     Replay creates no temporary view, index or retained row buffer.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-trrel-uf-replay-insert! state '(1 2) 4 (lambda (_) displayln))
;;     ;; => emits the same ordered rows as its frozen injection frontier
;;     ```
;;   %
(def (gerbil-ascent-trrel-uf-replay-insert! groups row budget writer)
  (admit-insertion! groups row budget
    (lambda (blocks count _units)
      (let (emit (writer count))
        (when emit (gerbil-ascent-write-rectangles! blocks emit))))))

;; Admission dispatch precedes rectangle planning. This branch alone owns
;; preflight and commit; an existing closure fact never enters the product scan.
;; : (forall (a) (-> UfState UfInsertion Natural (-> [Rectangle] Natural Natural a) Boolean a))
;; : (-> UfState UfInsertion Natural FrontierPublisher Boolean Publication)
(def (insert-components! groups admission budget finish rectangles?)
  (with (((uf-insertion group-key group row left-node right-node a b) admission))
  (let* ((width (car group-key)) (nodes (uf-group-nodes group))
         (pair (if (= width 3) (cdr row) row)) (left (car pair)) (right (cadr pair))
         (new (append (if left-node [] (list a))
                      (if (or right-node (eq? a b)) [] (list b))))
         (roots (append new (uf-group-roots group)))
         (population (+ (uf-group-population group) (length new)))
         (preds (cond ((not left-node) (list a))
                      ((uf-group-indexed? group)
                       (ordered-neighbors a (uf-node-predecessors a) roots population))
                      (else (filter (lambda (p) (reachable? p a)) roots))))
         (succs (cond ((not right-node) (list b))
                      ((uf-group-indexed? group)
                       (ordered-neighbors b (uf-node-reach b) roots population))
                      (else (filter (lambda (s) (reachable? b s)) roots))))
         ;; Capture the intersection in root order before adjacency mutation.
         ;; Succ(b) membership is already represented by b's reach table.
         (cycle (and (not (eq? a b)) (reachable? b a)
                     (filter (lambda (p) (reachable? b p)) preds)))
         (changes []) (needed (length new)) (added []))
    ;; Count each missing component rectangle before rows or graph mutation.
    (for-each (lambda (p)
      (for-each (lambda (s)
        (unless (reachable? p s)
          (set! needed (+ needed (* (uf-node-size p) (uf-node-size s))))
          (when rectangles? (set! changes (cons (cons p s) changes))))) succs)) preds)
    (when (> needed budget) (error "ASCENT trrel output fact budget exceeded"))
    (when rectangles?
    (let (prefix (if (= width 3) (list (car row)) []))
      (for-each (lambda (n)
        (let (members (uf-node-members n))
          (set! added (cons (make-rectangle prefix members members) added)))) new)
      (for-each (lambda (change)
        (set! added (cons (make-rectangle prefix
                           (uf-node-members (car change))
                           (uf-node-members (cdr change))) added))) changes)))
    ;; No callback occurs between preflight and commit. Budget rejection has
    ;; not installed new nodes, rewritten parents or altered adjacency.
    (unless (null? new)
      (hash-put! groups group-key group)
      (unless left-node (hash-put! nodes left a))
      (unless right-node (hash-put! nodes right b))
      (set! (uf-group-roots group) roots)
      (set! (uf-group-population group) population)
      (set! (uf-group-next-order group) (+ 2 (uf-group-next-order group))))
    ;; Keep small components on the cheaper legacy scan. Activate the reverse
    ;; map only after successful preflight, so rejected admission is read-only.
    (unless (uf-group-indexed? group)
      (when (> population 64)
        (set! (uf-group-indexed? group) #t)
        (rebuild-predecessors! roots)))
    ;; If every root collapses, all changed arcs would immediately disappear.
    ;; Concrete rectangles were emitted above; no external reach key survives.
    (def (commit-arc! p s)
        (hash-put! (uf-node-reach p) s #t)
        (when (uf-group-indexed? group)
          (hash-put! (uf-node-predecessors s) p #t)))
    (unless (and cycle (= (length cycle) population))
      (if rectangles?
        (for-each (lambda (change) (commit-arc! (car change) (cdr change))) changes)
        ;; Each root pair is unique. Installing its own arc changes no other
        ;; pair's admission test; no changes spine is needed for count consumers.
        (let (targets (reverse succs))
          (for-each (lambda (p)
            (for-each (lambda (s) (unless (reachable? p s) (commit-arc! p s))) targets))
            (reverse preds)))))
    ;; A new a->b edge makes precisely Pred(a) intersect Succ(b) cyclic.
    ;; Merge toward the largest component, bounding union parent depth.
    (when cycle
      (merge-cycle! group roots cycle))
    ;; The descriptor accumulator is private; member spines are persistent.
    (let (units (length added)) (finish (reverse! added) needed units)))))
;; Physical structure counts, not whole-engine memory or allocator receipts.
;; : (-> UfState (Vector Natural))
(def (gerbil-ascent-trrel-uf-observation groups)
  (let ((nodes 0) (components 0) (arcs 0))
    (hash-for-each (lambda (_ g)
      (set! nodes (+ nodes (hash-length (uf-group-nodes g))))
      (set! components (+ components (length (uf-group-roots g))))
      (for-each (lambda (n) (set! arcs (+ arcs (hash-length (uf-node-reach n)))))
                (uf-group-roots g))) groups)
    (vector nodes components arcs)))

;; Explicit qualification audit, never called on the insertion/query hot path.
;; This checks the concrete representation premises used by the proof layer.
;; gerbil-ascent-trrel-uf-validate
;; : (-> UfState Boolean)
;; | doc m%
;;     Audit private component ownership, canonical parent roots and closure.
;;     Validation observes state without path compression or graph mutation.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-trrel-uf-validate (gerbil-ascent-trrel-uf-state))
;;     ;; => #t
;;     ```
;;   %
(def (gerbil-ascent-trrel-uf-validate groups)
  (def (require! ok message) (unless ok (error message)))
  (def (unique? values same?)
    (match values
      ([] #t)
      ([head . tail] (and (not (ormap (cut same? head <>) tail)) (unique? tail same?)))))
  (def (checked-root node (seen []))
    (require! (not (memq node seen)) "ASCENT UF parent cycle")
    (match (uf-node-parent node)
      (#f node)
      (parent (checked-root parent (cons node seen)))))
  (hash-for-each (lambda (_ group)
    (let ((nodes (uf-group-nodes group)) (roots (uf-group-roots group)))
      (require! (= (uf-group-population group) (length roots)) "ASCENT UF root population mismatch")
      (require! (unique? roots eq?)
                "ASCENT UF duplicate root")
      (let loop ((remaining roots) (ceiling (+ 1 (uf-group-next-order group))))
        (unless (null? remaining)
          (let (order (uf-node-order (car remaining)))
            (require! (and (exact-integer? order) (> order 0) (< order ceiling))
                      "ASCENT UF root scan order mismatch")
            (loop (cdr remaining) order))))
      (hash-for-each (lambda (value node)
        (let (owner (checked-root node))
          (require! (memq owner roots) "ASCENT UF missing root")
          (require! (member value (uf-node-members owner)) "ASCENT UF missing member")
          (when (uf-node-parent node)
            (require! (and (null? (uf-node-members node)) (= (uf-node-size node) 0)
                           (= (hash-length (uf-node-reach node)) 0)
                           (not (uf-node-predecessors node)))
                      "ASCENT UF absorbed storage retained")))) nodes)
      (for-each (lambda (n)
        (let (members (uf-node-members n))
          (require! (not (uf-node-parent n)) "ASCENT UF non-root owner")
          (require! (and (> (uf-node-size n) 0) (= (uf-node-size n) (length members))
                         (unique? members equal?))
                    "ASCENT UF member size mismatch")
          (for-each (lambda (value)
            (let (node (hash-get nodes value))
              (require! (and node (eq? (checked-root node) n)) "ASCENT UF wrong member owner"))) members))
        (if (uf-group-indexed? group)
          (begin
            (require! (hash-table? (uf-node-predecessors n)) "ASCENT UF missing predecessor map")
            (hash-for-each (lambda (predecessor _)
              (require! (and (not (eq? n predecessor)) (memq predecessor roots)
                             (hash-get (uf-node-reach predecessor) n))
                        "ASCENT UF stale predecessor key")) (uf-node-predecessors n)))
          (require! (not (uf-node-predecessors n)) "ASCENT UF premature predecessor map"))
        (hash-for-each (lambda (target _)
          (when (uf-group-indexed? group)
            (require! (hash-get (uf-node-predecessors target) n) "ASCENT UF missing predecessor key"))
          (require! (and (not (eq? n target)) (memq target roots)) "ASCENT UF stale reach key")
          (hash-for-each (lambda (successor _)
            (require! (reachable? n successor) "ASCENT UF incomplete root closure"))
            (uf-node-reach target))) (uf-node-reach n))) roots))) groups)
  #t)

;; Explicit public frontier export preserves the original kernel API/order.
;; : (-> UfState Rows Rows Row Natural Rows)
(def (gerbil-ascent-trrel-uf-extension groups _all _pending row budget)
  (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-insert! groups row budget)))
;; Freeze root membership and reach into disjoint component rectangles. No
;; parent link or mutable reach table survives in the published representation.
;; : (-> UfState Boolean FrozenView)
(def (gerbil-ascent-trrel-uf-freeze groups (indexed? #t))
  (let ((blocks []) (count 0) (units 0))
    (hash-for-each (lambda (key group)
      (let ((members (make-hash-table-eq))
            (prefix (if (= (car key) 3) (list (cadr key)) [])))
        (for-each (lambda (node)
          ;; Merge replaces member fields with append-created spines and clears
          ;; absorbed records; it never mutates an existing member pair. Like
          ;; EqRel capture, borrow that immutable spine without retaining nodes.
          (let (owned (uf-node-members node))
            (set! units (+ units (uf-node-size node)))
            (hash-put! members node (make-frozen-members owned (uf-node-size node))))) (uf-group-roots group))
        (for-each (lambda (node)
          ;; Capture each source owner once. Counts come from committed SCC
          ;; metadata; no arc rescans a copied member spine for cardinality.
          (using (left (hash-get members node) :- frozen-members)
            (def (capture target)
              (using (right (hash-get members target) :- frozen-members)
                (set! count (+ count (* left.count right.count)))
                (set! units (+ units 1))
                (set! blocks (cons (make-rectangle prefix left.rows right.rows) blocks))))
            (capture node)
            (hash-for-each (lambda (target _) (capture target)) (uf-node-reach node))))
          (uf-group-roots group)))) groups)
    (gerbil-ascent-rectangle-view (reverse! blocks) count units indexed?)))

;; The proved Provider API and engine adapter share one frozen carrier/kernel.
(def gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-insert!)
(def gerbil-ascent-trrel-uf-snapshot gerbil-ascent-trrel-uf-freeze)
(def gerbil-ascent-trrel-uf-view-count relation-view-count)
;; : (-> FrozenView RowWriter Void)
(def (gerbil-ascent-trrel-uf-view-for-each view consume)
  (gerbil-ascent-for-each-row consume view))
;; : (-> FrozenView Columns Key Rows)
(def (gerbil-ascent-trrel-uf-view-lookup view columns key)
  (unless (and (list? columns) (list? key) (= (length columns) (length key))
               (andmap (lambda (column) (and (exact-integer? column) (>= column 0))) columns))
    (error "invalid ASCENT UF view key"))
  (let (rows [])
    (gerbil-ascent-for-each-row (lambda (row) (set! rows (cons row rows)))
                              (gerbil-ascent-view-select view columns key))
    (reverse rows)))


;; gerbil-ascent-trrel-uf-count-insert!
;; : (-> UfState Row Natural Natural)
;; | doc m%
;;     Admit and commit the same whole injection as the frozen frontier kernel,
;;     returning only its cardinality. No rectangle descriptors or emitted rows
;;     are needed for a fresh engine's callback-free initial source accounting.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-trrel-uf-count-insert! (gerbil-ascent-trrel-uf-state) '(0 1) 8)
;;     ;; => 3
;;     ```
;;   %
(def (gerbil-ascent-trrel-uf-count-insert! groups row budget)
  (admit-insertion! groups row budget (lambda (_blocks count _units) count) #f))
