;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Immutable six-slot plans become engine-owned seven-slot rule activations.
(export gerbil-ascent-activate-rule gerbil-ascent-activate-plans)
;; : (forall (a) (-> (Vector a) (Vector a)))
;; : (-> RulePlan RuleActivation)
(def (gerbil-ascent-activate-rule rule)
  (let (plan (vector-ref rule 5))
    (vector (vector-ref rule 0) (vector-ref rule 1)
            (vector-ref rule 2) (vector-ref rule 3) (vector-ref rule 4)
            plan (and plan (make-vector (vector-ref plan 2) #f)))))
;; : (forall (a) (-> (Vector [a]) (Vector [a])))
;; : (-> RulePlansByStratum ActiveRulesByStratum)
(def (gerbil-ascent-activate-plans plans)
  (vector-map (lambda (rules) (map gerbil-ascent-activate-rule rules)) plans))
