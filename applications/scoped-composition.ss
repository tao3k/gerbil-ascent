;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/objects
        :gerbil-ascent/applications/scoped-witness
        :gerbil-ascent/applications/scoped-reachability-mask)
(export gerbil-ascent-scoped-composition-program gerbil-ascent-compose-scoped-program
        gerbil-ascent-scoped-query-program gerbil-ascent-scoped-query-path)

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

;;; A normalized request compiles the entire P -> N -> C/D chain. Publication
;;; keeps a distance pointer for every required-group support of a final answer;
;;; mask_predecessor reconstructs its shortest path by decreasing that distance.
;; : (forall (v scope group) (-> [(Tuple v)] [(Pair v v)] [(Pair scope v)] [(Pair scope v)] [(Pair scope v)] [(Tuple group)] [(Pair group scope)] [(Pair v v)] Integer Integer Integer Integer Program))
;; : (-> VertexRows EdgeRows ScopedStarts ScopedTargets ScopedBlocked RequiredGroups GroupMembers CandidatePairs HopLimit InputBudget FactBudget OutputBudget Program)
(def (gerbil-ascent-scoped-query-program vertices edges starts targets blocked required members candidates hops
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (let* ((base (gerbil-ascent-compose-scoped-program
                (gerbil-ascent-bounded-scoped-reachability-mask-program
                  vertices edges starts targets blocked hops input-budget fact-budget output-budget)
                required members candidates))
         (g (gerbil-ascent-variable 'group)) (scope (gerbil-ascent-variable 'scope))
         (s (gerbil-ascent-variable 's)) (t (gerbil-ascent-variable 't))
         (k (gerbil-ascent-variable 'k)))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (gerbil-ascent-program
      (append (.ref base 'relations) (list (gerbil-ascent-relation 'answer_trace 5 [])))
      (append (.ref base 'rules)
        (list (gerbil-ascent-rule (list (a 'answer_trace g scope s t k))
          (list (a 'group_answer s t) (a 'group_witness g scope s t)
                (a 'mask_shortest s t k)))))
      input-budget fact-budget output-budget (.ref base 'source-handles))))

;;; Reconstruct one shortest producer path from a completed published cut.
;;; Scope admission is carried by answer_trace; an unmasked producer path alone
;;; is not evidence that its endpoint pair survived any particular scope.
;; : (forall (v) (-> EvaluationResult v v (Maybe [v])))
;; : (-> EvaluationResult Vertex Vertex OptionalPath)
(def (gerbil-ascent-scoped-query-path result s t)
  (unless (.ref result 'finished) (error "ASCENT scoped query path requires completed execution"))
  (let ((visit (.ref result 'visit-rows)) (distance #f))
    (visit 'mask_shortest '(0 1) (list s t) (lambda (row) (set! distance (caddr row))))
    (and distance
      (let loop ((target t) (remaining distance) (path (list t)))
        (if (zero? remaining)
          (begin (unless (equal? s target) (error "ASCENT scoped query path has invalid zero-hop root")) path)
          (let (previous #f)
            (visit 'mask_predecessor '(0 2 3) (list s target remaining)
              (lambda (row) (unless previous (set! previous (list (cadr row))))))
            (unless previous (error "ASCENT scoped query path is missing a predecessor"))
            (loop (car previous) (- remaining 1) (cons (car previous) path))))))))
