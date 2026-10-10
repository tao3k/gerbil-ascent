;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider))
(export gerbil-ascent-finite-flow-program)
;; : (-> FactWidth PointDomain SeedMasks CfgEdges BlockMasks InputBudget FactBudget OutputBudget Program)
;; A source row is (Point, immutable nonnegative integer mask). Domain width is
;; fixed for this Program. Session updates replace or append masks, not domains.
;; The blocker aggregate is strict: adding a blocker can withdraw prior facts.
;; Opaque procedures deliberately select Session replay and ordered evaluation.
;; Budgets below charge packed Program rows, not decoded logical facts; gamma
;; publication separately charges its logical cardinality.
(def (gerbil-ascent-finite-flow-program width points seeds edges blockers
                                        input-budget fact-budget output-budget)
  (unless (and (exact-integer? width) (>= width 0) (list? points))
    (error "invalid ASCENT finite flow Program domain"))
  (let ((domain (make-hash-table)) (limit (arithmetic-shift 1 width)))
    (for-each (lambda (p)
      (when (hash-get domain p) (error "duplicate ASCENT finite flow Program point" p))
      (hash-put! domain p #t)) points)
    (def (point? p) (and (hash-get domain p) #t))
    (def (mask? m) (and (exact-integer? m) (<= 0 m) (< m limit)))
    (def (v name) (gerbil-ascent-variable name))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'flow_point 1 (map list points)
              gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider (list point?))
            (gerbil-ascent-relation 'flow_seed 2 seeds
              gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider (list point? mask?))
            (gerbil-ascent-relation 'flow_edge 2 edges
              gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider (list point? point?))
            (gerbil-ascent-relation 'flow_block 2 blockers
              gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider (list point? mask?))
            (gerbil-ascent-relation 'flow_blocked 2 []
              gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider (list point? mask?))
            (gerbil-ascent-lattice 'flow_state 2 [] bitwise-ior
              gerbil-ascent-hash-index-provider (list point? mask?)))
      (list
        (gerbil-ascent-rule (list (a 'flow_blocked (v 'p) (v 'blocked)))
          (list (a 'flow_point (v 'p))
            (gerbil-ascent-aggregate 'blocked 'flow_block (list (v 'p) (v 'm)) '(m)
              (lambda (tuples) (list (foldl (lambda (row mask) (bitwise-ior mask (car row))) 0 tuples))))))
        (gerbil-ascent-rule (list (a 'flow_state (v 'p) (v 'm)))
          (list (a 'flow_seed (v 'p) (v 'm))))
        (gerbil-ascent-rule (list (a 'flow_state (v 'q) (v 'fresh)))
          (list (a 'flow_state (v 'p) (v 'm)) (a 'flow_edge (v 'p) (v 'q))
            (a 'flow_blocked (v 'q) (v 'blocked))
            (gerbil-ascent-binding 'fresh '(m blocked)
              (lambda (m blocked) (bitwise-and m (bitwise-not blocked)))))))
      input-budget fact-budget output-budget)))
