;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        :gerbil-ascent/applications/scoped-witness)
(export gerbil-ascent-scoped-composition-program gerbil-ascent-compose-scoped-program)

;;; Scope exclusion belongs to the existing branch Program. Group composition
;;; keeps explicit candidate pairs and required groups, including empty groups.
;;; A missing group blocks publication; no required groups is vacuously true
;;; only inside the caller's finite candidate relation.
;; : (forall (v scope group) (-> [(Pair v v)] [(Pair scope v)] [(Pair scope v)] [(Pair scope v)] [(Triple scope v v)] [(Tuple group)] [(Pair group scope)] [(Pair v v)] Integer Integer Integer Program))
;; : (-> EdgeRows ScopedStarts ScopedTargets ScopedBlocked ScopedDirect RequiredGroups GroupMembers CandidatePairs InputBudget FactBudget OutputBudget Program)
(def (gerbil-ascent-scoped-composition-program edges starts targets blocked direct
        required members candidates
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (gerbil-ascent-compose-scoped-program
    (gerbil-ascent-branch-scoped-witness-program
      edges starts targets blocked direct input-budget fact-budget output-budget)
    required members candidates))

;;; Compose an admitted declaration tree exposing branch_answer(scope,s,t).
;;; Preserve producer budgets and source handles; the ordinary Program contract
;;; and admission own relation collisions, arities and stratification.
;; : (forall (v scope group) (-> Program [(Tuple group)] [(Pair group scope)] [(Pair v v)] Program))
;; : (-> Program RequiredGroups GroupMembers CandidatePairs Program)
(def (gerbil-ascent-compose-scoped-program base required members candidates)
  (let ((g (gerbil-ascent-variable 'group)) (scope (gerbil-ascent-variable 'scope))
        (s (gerbil-ascent-variable 's)) (t (gerbil-ascent-variable 't)))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (append (.ref base 'relations)
        (list (gerbil-ascent-relation 'group_required 1 required)
              (gerbil-ascent-relation 'group_member 2 members)
              (gerbil-ascent-relation 'group_candidate 2 candidates)
              (gerbil-ascent-relation 'group_witness 4 [])
              (gerbil-ascent-relation 'group_support 3 [])
              (gerbil-ascent-relation 'group_missing 3 [])
              (gerbil-ascent-relation 'group_failure 2 [])
              (gerbil-ascent-relation 'group_answer 2 [])))
      (append (.ref base 'rules)
        (list
          (gerbil-ascent-rule (list (a 'group_witness g scope s t))
            (list (a 'group_candidate s t) (a 'group_required g)
                  (a 'group_member g scope) (a 'branch_answer scope s t)))
          (gerbil-ascent-rule (list (a 'group_support g s t))
            (list (a 'group_witness g scope s t)))
          (gerbil-ascent-rule (list (a 'group_missing g s t))
            (list (a 'group_candidate s t) (a 'group_required g)
                  (gerbil-ascent-negation 'group_support (list g s t))))
          (gerbil-ascent-rule (list (a 'group_failure s t))
            (list (a 'group_missing g s t)))
          (gerbil-ascent-rule (list (a 'group_answer s t))
            (list (a 'group_candidate s t)
                  (gerbil-ascent-negation 'group_failure (list s t))))))
      (.ref base 'max-input-facts) (.ref base 'max-derived-facts)
      (.ref base 'max-output-facts) (.ref base 'source-handles))))
