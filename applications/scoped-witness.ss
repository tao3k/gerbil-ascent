;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; MatLogic finite two-hop transfer: exclude only the intermediate witness
;;; before answer projection. Direct support is a separate, unmasked branch.
(import :gerbil-ascent/program/objects)
(export gerbil-ascent-scoped-witness-program
        gerbil-ascent-branch-scoped-witness-program)
(def (gerbil-ascent-scoped-witness-program edges starts targets blocked direct
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (let ((s (gerbil-ascent-variable 's)) (w (gerbil-ascent-variable 'w))
        (t (gerbil-ascent-variable 't)))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'scope_edge 2 edges)
            (gerbil-ascent-relation 'scope_start 1 starts)
            (gerbil-ascent-relation 'scope_target 1 targets)
            (gerbil-ascent-relation 'scope_blocked 1 blocked)
            (gerbil-ascent-relation 'scope_direct 2 direct)
            (gerbil-ascent-relation 'scope_witness 3 [])
            (gerbil-ascent-relation 'scope_answer 2 []))
      (list
        (gerbil-ascent-rule (list (a 'scope_witness s w t))
          (list (a 'scope_start s) (a 'scope_edge s w) (a 'scope_edge w t)
                (a 'scope_target t) (gerbil-ascent-negation 'scope_blocked (list w))))
        (gerbil-ascent-rule (list (a 'scope_answer s t))
          (list (a 'scope_witness s w t)))
        (gerbil-ascent-rule (list (a 'scope_answer s t))
          (list (a 'scope_start s) (a 'scope_direct s t) (a 'scope_target t))))
      input-budget fact-budget output-budget)))

;;; Branch identities remain in input selections, masks, witnesses and answers.
;;; Only branch_union deliberately projects the identity away after exclusion.
;;; Edges are shared; direct support remains unmasked inside its own branch.
(def (gerbil-ascent-branch-scoped-witness-program edges starts targets blocked direct
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (let ((scope (gerbil-ascent-variable 'scope)) (s (gerbil-ascent-variable 's))
        (w (gerbil-ascent-variable 'w)) (t (gerbil-ascent-variable 't)))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'branch_edge 2 edges)
            (gerbil-ascent-relation 'branch_start 2 starts)
            (gerbil-ascent-relation 'branch_target 2 targets)
            (gerbil-ascent-relation 'branch_blocked 2 blocked)
            (gerbil-ascent-relation 'branch_direct 3 direct)
            (gerbil-ascent-relation 'branch_witness 4 [])
            (gerbil-ascent-relation 'branch_answer 3 [])
            (gerbil-ascent-relation 'branch_union 2 []))
      (list
        (gerbil-ascent-rule (list (a 'branch_witness scope s w t))
          (list (a 'branch_start scope s) (a 'branch_edge s w) (a 'branch_edge w t)
                (a 'branch_target scope t)
                (gerbil-ascent-negation 'branch_blocked (list scope w))))
        (gerbil-ascent-rule (list (a 'branch_answer scope s t))
          (list (a 'branch_witness scope s w t)))
        (gerbil-ascent-rule (list (a 'branch_answer scope s t))
          (list (a 'branch_start scope s) (a 'branch_direct scope s t)
                (a 'branch_target scope t)))
        (gerbil-ascent-rule (list (a 'branch_union s t))
          (list (a 'branch_answer scope s t))))
      input-budget fact-budget output-budget)))
