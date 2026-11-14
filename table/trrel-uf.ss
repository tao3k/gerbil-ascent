;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private union-find SCCs and reachability between component roots.
;;; Concrete frontier rows are returned, never retained in this provider.
(import "uf-reach.ss" (only-in :std/list/list length<=n?)
        :gerbil-ascent/core/relation-view (only-in :std/vector/extensible make-ExtensibleVector ExtensibleVector-ref
                 ExtensibleVector-set! ExtensibleVector-fill-pointer
                 ExtensibleVector-fill-pointer-set! ExtensibleVector->list))
(export gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-freeze
        gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension
        gerbil-ascent-trrel-uf-frontier-extension gerbil-ascent-trrel-uf-snapshot
        gerbil-ascent-trrel-uf-view-count gerbil-ascent-trrel-uf-view-for-each
        gerbil-ascent-trrel-uf-view-lookup
        gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-resource-observation gerbil-ascent-trrel-uf-validate
        gerbil-ascent-trrel-uf-replay-insert! gerbil-ascent-trrel-uf-count-insert!
        gerbil-ascent-trrel-uf-cycle-vertices gerbil-ascent-trrel-uf-commit-source-cycle!)

;; Borrow the edge spine only during recognition. The private vector retains
;; immutable endpoint values in injection order.
(def (gerbil-ascent-trrel-uf-cycle-vertices rows)
  (and (length<=n? rows 512) (list? rows)
       (let (width (length rows))
         (and (>= width 2)
              (let ((vertices (make-vector width)) (seen (make-hash-table-eqv size: width)))
                (let scan ((pending rows) (rank 0) (next #f))
                  (match pending
                    ([] (and (= next (vector-ref vertices 0)) vertices))
                    ([[left right] . rest]
                     (and (fixnum? left) (fixnum? right)
                          (or (zero? rank) (= left next))
                          (not (hash-key? seen left))
                          (begin
                            (hash-put! seen left #t)
                            (vector-set! vertices rank left)
                            (scan rest (+ rank 1) right))))
                    (else #f))))))))
(def (rebuild-predecessors! group roots)
  (for-each (lambda (n) (set! (uf-node-predecessors n) (make-hash-table-eq))) roots)
  (for-each (lambda (n)
    (reach-for-each (lambda (target _)
      (set! (uf-node-predecessors target) (reach-put! (uf-node-predecessors target) n group))) (uf-node-reach n))) roots))
;; The group owns its newest-first roster. The unchanged suffix predates
;; every retired root; splice only the freshly allocated prefix onto it.
(def (prune-cycle-roots roots oldest)
  (let loop ((remaining roots) (kept []))
    (match remaining
      ([] (reverse! kept))
      ([node . rest]
       (if (< (uf-node-order node) oldest)
         (append-reverse! kept remaining)
         (loop rest (if (uf-node-parent node) kept (cons node kept))))))))

;; All missing arcs have been committed, except on a whole-group collapse.
;; In that closed graph any surviving owner adjacent to a loser is adjacent
;; to the winner. Remove loser keys from the winner first. Its two remaining
;; rows then name exactly the external owners to update, without scanning
;; the group or allocating a copy of either adjacency row.
;; : (-> UfGroup [UfNode] [UfNode] Void)
(def (merge-cycle! group roots cycle)
  (let* ((winner (foldl (lambda (node best)
                         (if (> (uf-node-size node) (uf-node-size best)) node best))
                       (car cycle) (cdr cycle)))
         (cycle-size (length cycle))
         (remaining (- (+ 1 (uf-group-population group)) cycle-size))
         (whole-group? (= remaining 1))
         (indexed? (uf-group-indexed? group))
         (retired (and (not whole-group?) (cycle-mask group cycle)))
         (losers (filter (lambda (node) (not (eq? node winner))) cycle))
         (merged (uf-node-members winner))
         (size (uf-node-size winner))
         (oldest #f))
    (def (retire-keys table)
      (if (and retired (compact-reach? table))
        (reach-remove-mask! table retired)
        (for-each (lambda (node) (reach-remove! table node)) losers))
      (reach-retired table))
    (when retired (reach-remove! retired winner))
    (if whole-group?
      (begin
        (set! (uf-node-reach winner) (make-hash-table-eq))
        (when indexed?
          (set! (uf-node-predecessors winner) (make-hash-table-eq))))
      (begin
        (let (table (retire-keys (uf-node-reach winner)))
          (set! (uf-node-reach winner)
            (if (zero? (reach-length table)) (make-hash-table-eq) table)))
        (if indexed?
          (begin
            (set! (uf-node-predecessors winner) (retire-keys (uf-node-predecessors winner)))
            (reach-for-each (lambda (owner _)
              (set! (uf-node-reach owner) (retire-keys (uf-node-reach owner))))
              (uf-node-predecessors winner))
            (reach-for-each (lambda (owner _)
              (set! (uf-node-predecessors owner) (retire-keys (uf-node-predecessors owner))))
              (uf-node-reach winner)))
          ;; The small-group path has no reverse index. Only a surviving
          ;; predecessor of the winner can own a forward key to a loser.
          (for-each (lambda (owner)
            (when (reach-get (uf-node-reach owner) winner)
              (unless (memq owner losers)
                (set! (uf-node-reach owner) (retire-keys (uf-node-reach owner)))))) roots))))
    (for-each (lambda (node)
      (let (order (uf-node-order node))
        (set! oldest (if oldest (min oldest order) order))
        (when (and (not whole-group?) (uf-group-registry group))
          (ExtensibleVector-set! (uf-group-registry group) order #f)))
      (set! merged (append (uf-node-members node) merged))
      (set! size (+ size (uf-node-size node)))
      (set! (uf-node-parent node) winner)
      (set! (uf-node-members node) [])
      (set! (uf-node-size node) 0)
      ;; Endpoint lookup follows the parent before reading adjacency. A retired
      ;; node retains its identity for that lookup, with no adjacency owner.
      (set! (uf-node-reach node) #f)
      (set! (uf-node-predecessors node) #f)) losers)
    (set! (uf-node-members winner) merged)
    (set! (uf-node-size winner) size)
    (set! (uf-group-population group) remaining)
    (set! (uf-group-roots group)
      (if whole-group? (list winner) (prune-cycle-roots roots oldest)))
    (when whole-group? (set! (uf-group-registry group) #f))))

;; The source owner has admitted every prefix on a fresh group. The open
;; chain's arcs all disappear at closure. Build the same singleton roster
;; and let the ordinary collapse choose the winner and merge its members.
(def (gerbil-ascent-trrel-uf-commit-source-cycle! groups vertices)
  (let* ((width (vector-length vertices))
         (indexed? (> width 64))
         (nodes (make-hash-table size: width)))
    (def (birth rank order)
      (let* ((value (vector-ref vertices rank)) (node (fresh value order indexed?)))
        (hash-put! nodes value node)
        node))
    (let* ((first (birth 0 2))
           (second (birth 1 1))
           (roots (let build ((rank 2) (roots (list first second)))
                    (if (= rank width) roots
                      (build (+ rank 1) (cons (birth rank (- (* 2 rank) 1)) roots)))))
           (group (make-uf-group nodes roots (* 2 (- width 1)) indexed? width #f)))
      (merge-cycle! group roots roots)
      (hash-put! groups '(2 #f) group))))

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
         (group (or stored (make-uf-group (make-hash-table) [] 0 #f 0 #f)))
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
         (fresh-product? (and (not (eq? a b)) (or (not left-node) (not right-node))))
         (closes-cycle? (and (not (eq? a b)) (reachable? b a)))
         (preds (cond ((not left-node) (list a))
                      ((and (not rectangles?) (not (eq? a b)) (not closes-cycle?) (uf-group-indexed? group)
                            (compact-reach? (uf-node-predecessors a)))
                       (make-closure-axis a (uf-node-predecessors a)))
                      ((uf-group-indexed? group)
                       (ordered-neighbors a (uf-node-predecessors a) roots population (not rectangles?)))
                      (else (select-neighbors (lambda (p) (reachable? p a)) roots (not rectangles?)))))
         ;; Capture the intersection in root order before adjacency mutation.
         ;; Succ(b) membership is already represented by b's reach table.
         (cycle (and closes-cycle?
                     (if rectangles?
                       (filter (lambda (p) (reachable? b p)) preds)
                       (foldl (lambda (p selected)
                         (if (reachable? b p) (cons p selected) selected)) [] preds))))
         (whole-group? (and cycle (= (length cycle) population)))
         (singleton? (= (uf-group-population group) (hash-length nodes)))
         ;; A count-only closure over all singleton roots needs only the
         ;; existing row degrees. Materialized frontiers still use the
         ;; ordered difference, including every missing rectangle.
         (count-square? (and (not rectangles?) whole-group? singleton?))
         (succs (cond (count-square? [])
                      ((not right-node) (list b))
                      ((and (not rectangles?) (not (eq? a b)) (not closes-cycle?)
                            (compact-reach? (uf-node-reach b)))
                       (make-closure-axis b (uf-node-reach b)))
                      ((uf-group-indexed? group)
                       (ordered-neighbors b (uf-node-reach b) roots population (not rectangles?)))
                      (else (select-neighbors (lambda (s) (reachable? b s)) roots (not rectangles?)))))
         ;; A fresh source or sink has no external arc. Every pair on these
         ;; axes is missing; self-injections retain ordinary admission.
         (changes []) (needed (length new)) (added [])
         (target-mask (and (not count-square?) (not fresh-product?)
                           (uf-group-indexed? group) (reach-copyable? (uf-node-reach b) b)
                           (reach-copy-with-node (uf-node-reach b) b)))
         (excess (and target-mask (target-excess target-mask succs singleton?)))
         (target-weight (and target-mask (axis-weight succs singleton?))))
    ;; Count each missing component rectangle before rows or graph mutation.
    (cond
     (count-square?
      (set! needed
        (foldl (lambda (node missing)
                 (+ missing (- population 1 (reach-length (uf-node-reach node)))))
               0 cycle)))
     ((and fresh-product? (not rectangles?))
      (set! needed (+ needed
        (* (axis-weight preds singleton?) (axis-weight succs singleton?)))))
     (else
      (axis-for-each (lambda (p)
        (if target-mask
          (set! needed (+ needed (reach-difference-weight target-mask p excess target-weight)))
          (axis-for-each (lambda (s)
            (when (or fresh-product? (not (reachable? p s)))
              (set! needed (+ needed (* (uf-node-size p) (uf-node-size s))))
              (when (and rectangles? (not target-mask)) (set! changes (cons (cons p s) changes))))) succs))) preds)))
    (when (> needed budget) (error "ASCENT trrel output fact budget exceeded"))
    (when rectangles?
    (let (prefix (if (= width 3) (list (car row)) []))
      (for-each (lambda (n)
        (let (members (uf-node-members n))
          (set! added (cons (make-rectangle prefix members members) added)))) new)
      (when target-mask
        (let (blocks (difference-rectangles prefix target-mask preds succs))
          (set! added (if (null? added) blocks (append blocks added)))))
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
      (set! (uf-group-next-order group) (+ 2 (uf-group-next-order group)))
      (when (uf-group-registry group)
        (let (registry (uf-group-registry group))
          ;; Native fill-pointer growth captures a continuation. Enter it only
          ;; at geometric reserved-span boundaries, not for every admitted birth.
          (when (>= (uf-group-next-order group) (ExtensibleVector-fill-pointer registry))
            (ExtensibleVector-fill-pointer-set! registry
              (arithmetic-shift 1 (integer-length (uf-group-next-order group))) #f 1))
          (for-each (lambda (n) (ExtensibleVector-set! registry (uf-node-order n) n)) new))))
    ;; Keep small components on the cheaper legacy scan. Activate the reverse
    ;; map only after successful preflight, so rejected admission is read-only.
    (unless (uf-group-indexed? group)
      (when (> population 64)
        (set! (uf-group-indexed? group) #t)
        (rebuild-predecessors! group roots)))
    ;; Only a dense admitted fresh axis qualifies for whole-buffer transfer.
    ;; Existing endpoints still require ordinary missing-pair checks. Sparse
    ;; axes preserve their cheaper scalar path and original insertion order.
    (def copied-sources?
      (and fresh-product? (not right-node) (uf-group-indexed? group)
           (reach-copyable? (uf-node-predecessors a) a)))
    (def copied-targets?
      (and fresh-product? (not left-node)
           (reach-copyable? (uf-node-reach b) b)))
    (when copied-sources?
      (set! (uf-node-predecessors b)
        (reach-copy-with-node (uf-node-predecessors a) a)))
    (when copied-targets?
      (set! (uf-node-reach a) (reach-copy-with-node (uf-node-reach b) b)))
    ;; If every root collapses, all changed arcs would immediately disappear.
    ;; Concrete rectangles were emitted above; no external reach key survives.
    (def (commit-arc! p s)
        (unless copied-targets?
          (set! (uf-node-reach p) (reach-put! (uf-node-reach p) s group)))
        (when (and (uf-group-indexed? group) (not copied-sources?))
          (set! (uf-node-predecessors s) (reach-put! (uf-node-predecessors s) p group))))
    (unless whole-group?
      (if (and rectangles? (not target-mask))
        (for-each (lambda (change) (commit-arc! (car change) (cdr change))) changes)
        ;; Each root pair is unique. Installing its own arc changes no other
        ;; pair's admission test; no changes spine is needed for count consumers.
        ;; Count axes were selected directly in the original writer order.
        ;; SCC selection separately restored its original root order.
        (let ((sources preds) (targets succs))
          ;; A singleton sink needs one writer for the whole source axis,
          ;; rather than a newly captured inner writer for every source root.
          (match targets
            ([target]
             (axis-for-each (lambda (p)
               (when (or fresh-product? (not (reachable? p target)))
                 (commit-arc! p target))) sources))
            (else
             (axis-for-each (lambda (p)
               (if (and target-mask (compact-reach? (uf-node-reach p)))
                 (reach-difference-commit! target-mask p group)
                 (axis-for-each (lambda (s)
                   (when (or fresh-product? (not (reachable? p s)))
                     (commit-arc! p s))) targets))) sources))))))
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
      (for-each (lambda (n) (set! arcs (+ arcs (reach-length (uf-node-reach n)))))
                (uf-group-roots g))) groups)
    (vector nodes components arcs)))

;; Physical allocation units, not byte sizes or a whole-engine memory estimate.
;; Fields: sparse entries, occupied words, packed arcs, live registry keys,
;; bitmap payload bytes and registry backing-vector slots (including holes).
;; Both forward and reverse adjacency are counted; the registry is counted once.
;; : (-> UfState (Vector Natural))
(def (gerbil-ascent-trrel-uf-resource-observation groups)
  (let ((sparse 0) (chunks 0) (packed 0) (registry 0) (bytes 0) (slots 0))
    (def (account table)
      (when table
        (if (compact-reach? table)
          (begin (let (bits (compact-reach-bits table))
                   (set! bytes (+ bytes (* 4 (##u32vector-length bits))))
                   (let loop ((i 0))
                     (when (< i (##u32vector-length bits))
                       (unless (zero? (##u32vector-ref bits i)) (set! chunks (+ chunks 1)))
                       (loop (+ i 1)))))
                 (set! packed (+ packed (compact-reach-size table))))
          (set! sparse (+ sparse (hash-length table))))))
    (hash-for-each (lambda (_ group)
      (when (uf-group-registry group)
        (set! registry (+ registry (uf-group-population group)))
        (set! slots (+ slots (length (ExtensibleVector->list (uf-group-registry group))))))
      (for-each (lambda (n) (account (uf-node-reach n)) (account (uf-node-predecessors n)))
                (uf-group-roots group))) groups)
    (vector sparse chunks packed registry bytes slots)))

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
      (when (uf-group-registry group)
        (require! (= (length (filter identity (ExtensibleVector->list (uf-group-registry group)))) (length roots)) "ASCENT UF registry population mismatch")
        (for-each (lambda (n)
          (require! (eq? n (ExtensibleVector-ref (uf-group-registry group) (uf-node-order n))) "ASCENT UF registry owner mismatch")) roots))
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
                           (not (uf-node-reach node))
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
        (for-each (lambda (table)
          (when (and table (compact-reach? table))
            (require! (eq? (compact-reach-registry table) (uf-group-registry group)) "ASCENT UF wrong bit registry")
            (let (degree 0)
              (reach-for-each (lambda (target _) (require! target "ASCENT UF missing bit owner")
                               (set! degree (+ degree 1))) table)
              (require! (= degree (compact-reach-size table)) "ASCENT UF bit cardinality mismatch"))))
          (list (uf-node-reach n) (uf-node-predecessors n)))
        (if (uf-group-indexed? group)
          (begin
            (require! (or (hash-table? (uf-node-predecessors n)) (compact-reach? (uf-node-predecessors n))) "ASCENT UF missing predecessor map")
            (reach-for-each (lambda (predecessor _)
              (require! (and (not (eq? n predecessor)) (memq predecessor roots)
                             (reach-get (uf-node-reach predecessor) n))
                        "ASCENT UF stale predecessor key")) (uf-node-predecessors n)))
          (require! (not (uf-node-predecessors n)) "ASCENT UF premature predecessor map"))
        (reach-for-each (lambda (target _)
          (when (uf-group-indexed? group)
            (require! (reach-get (uf-node-predecessors target) n) "ASCENT UF missing predecessor key"))
          (require! (and (not (eq? n target)) (memq target roots)) "ASCENT UF stale reach key")
          (reach-for-each (lambda (successor _)
            (require! (reachable? n successor) "ASCENT UF incomplete root closure"))
            (uf-node-reach target))) (uf-node-reach n))) roots))) groups)
  #t)

;; Explicit public frontier export preserves the original kernel API/order.
;; : (-> UfState Rows Rows Row Natural Rows)
(def (gerbil-ascent-trrel-uf-extension groups _all _pending row budget)
  (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-insert! groups row budget)))
;; Freeze root membership and reach into disjoint component rectangles. No
;; parent link or mutable reach table survives in the published representation.
;;; Snapshot target axes in the same order as the descriptor writer: source
;;; diagonal first, then compact birth order. Only the new right spine is owned;
;;; member spines remain persistent and frozen records retain no mutable nodes.
;; : (-> UfState Boolean FrozenView)
(def (freeze-singleton-axis left reach slots)
  (let ((rights []) (mass 0))
    (def (capture record)
      (using (right record :- frozen-members)
        (set! mass (+ mass right.count))
        (for-each (lambda (value) (set! rights (cons value rights))) right.rows)))
    (capture left)
    (compact-reach-for-each-id (lambda (id) (capture (vector-ref slots id))) reach)
    (values (reverse! rights) mass)))
(def (gerbil-ascent-trrel-uf-freeze groups (indexed? #t))
  (let ((blocks []) (count 0) (units 0))
    ;; Sparse adjacency already names live roots directly. The owner
    ;; supplies a stable read and only member spines escape this traversal.
    (def (capture-sparse-group! roots prefix)
      (for-each
        (lambda (node)
          (let ((left (uf-node-members node)) (size (uf-node-size node)))
            (def (capture target _)
              (set! count (+ count (* size (uf-node-size target))))
              (set! units (+ units 1))
              (set! blocks
                (cons (make-rectangle prefix left (uf-node-members target)) blocks)))
            (set! units (+ units size))
            (capture node #t)
            (hash-for-each capture (uf-node-reach node))))
        roots))
    (def (capture-group! roots prefix)
      (let* ((span (foldl (lambda (n bound)
                     (let (reach (uf-node-reach n))
                       (if (compact-reach? reach)
                         (max bound (* 32 (##u32vector-length (compact-reach-bits reach)))) bound))) 0 roots))
             ;; Capture-only member references, bounded by existing bitmap span.
             ;; Sparse births beyond that span do not enlarge this array.
             (slots (and (> span 0) (make-vector span #f)))
             (members (make-hash-table-eq)))
        (for-each (lambda (node)
          ;; Merge replaces member fields with append-created spines and clears
          ;; absorbed records; it never mutates an existing member pair. Like
          ;; EqRel capture, borrow that immutable spine without retaining nodes.
          (let (owned (uf-node-members node))
            (set! units (+ units (uf-node-size node)))
            (let (record (make-frozen-members owned (uf-node-size node)))
              (hash-put! members node record)
              (when (and slots (< (uf-node-order node) span))
                (vector-set! slots (uf-node-order node) record))))) roots)
        (for-each (lambda (node)
          ;; Capture each source owner once. Counts come from committed SCC
          ;; metadata; no arc rescans a copied member spine for cardinality.
          (using (left (hash-get members node) :- frozen-members)
            (def reach (uf-node-reach node))
            (def (capture record)
              (using (right record :- frozen-members)
                (set! count (+ count (* left.count right.count)))
                (set! units (+ units 1))
                (set! blocks (cons (make-rectangle prefix left.rows right.rows) blocks))))
            (if (and (= left.count 1) (compact-reach? reach) (> (compact-reach-size reach) 0))
              (let-values (((rights mass) (freeze-singleton-axis left reach slots)))
                (set! count (+ count mass))
                ;; Include the copied member cells as well as the descriptor;
                ;; physical units are heterogeneous, not an allocation counter.
                (set! units (+ units mass 1))
                (set! blocks (cons (make-rectangle prefix left.rows rights) blocks)))
              (begin
                (capture left)
                (if (compact-reach? reach)
                  (compact-reach-for-each-id (lambda (id) (capture (vector-ref slots id))) reach)
                  (hash-for-each (lambda (target _) (capture (hash-get members target))) reach))))))
          roots)))
    (hash-for-each
      (lambda (key group)
        (let ((roots (uf-group-roots group))
              (prefix (if (= (car key) 3) (list (cadr key)) [])))
          (if (and (pair? roots) (null? (cdr roots))
                   (zero? (reach-length (uf-node-reach (car roots)))))
            ;; The closed owner needs no routing index. Both axes borrow the
            ;; same immutable members as the general capture.
            (let* ((owner (car roots))
                   (rows (uf-node-members owner))
                   (size (uf-node-size owner)))
              (set! count (+ count (* size size)))
              (set! units (+ units size 1))
              (set! blocks (cons (make-rectangle prefix rows rows) blocks)))
            (if (uf-group-registry group)
              (capture-group! roots prefix)
              (capture-sparse-group! roots prefix)))))
      groups)
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
  (gerbil-ascent-view-rows view columns key))


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
