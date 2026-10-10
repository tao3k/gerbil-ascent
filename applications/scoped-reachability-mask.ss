;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/objects)
(export gerbil-ascent-scoped-reachability-mask-program)

;;; Reflexive closure on caller vertices; structural exclusion removes an entire
;;; reachable pair if any banned vertex lies on any walk between its endpoints.
;;; This is finite least closure, not the paper's bounded K-hop matrix executor.
;; : (forall (v scope) (-> [(Tuple v)] [(Pair v v)] [(Pair scope v)] [(Pair scope v)] [(Pair scope v)] Integer Integer Integer Program))
;; : (-> VertexRows EdgeRows ScopedStarts ScopedTargets ScopedBlocked InputBudget FactBudget OutputBudget Program)
(def (gerbil-ascent-scoped-reachability-mask-program vertices edges starts targets blocked
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (let ((scope (gerbil-ascent-variable 'scope)) (s (gerbil-ascent-variable 's))
        (x (gerbil-ascent-variable 'x)) (t (gerbil-ascent-variable 't))
        (z (gerbil-ascent-variable 'z)))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'mask_vertex 1 vertices)
            (gerbil-ascent-relation 'mask_edge 2 edges)
            (gerbil-ascent-relation 'mask_start 2 starts)
            (gerbil-ascent-relation 'mask_target 2 targets)
            (gerbil-ascent-relation 'mask_blocked 2 blocked)
            (gerbil-ascent-relation 'mask_reach 2 [])
            (gerbil-ascent-relation 'mask_witness 4 [])
            (gerbil-ascent-relation 'mask_rejected 3 [])
            (gerbil-ascent-relation 'branch_answer 3 []))
      (list
        (gerbil-ascent-rule (list (a 'mask_reach s s)) (list (a 'mask_vertex s)))
        (gerbil-ascent-rule (list (a 'mask_reach s t))
          (list (a 'mask_reach s x) (a 'mask_edge x t) (a 'mask_vertex t)))
        (gerbil-ascent-rule (list (a 'mask_witness scope s z t))
          (list (a 'mask_start scope s) (a 'mask_target scope t)
                (a 'mask_blocked scope z) (a 'mask_reach s z) (a 'mask_reach z t)))
        (gerbil-ascent-rule (list (a 'mask_rejected scope s t))
          (list (a 'mask_witness scope s z t)))
        (gerbil-ascent-rule (list (a 'branch_answer scope s t))
          (list (a 'mask_start scope s) (a 'mask_target scope t) (a 'mask_reach s t)
                (gerbil-ascent-negation 'mask_rejected (list scope s t)))))
      input-budget fact-budget output-budget)))
