;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref) :gerbil-ascent/program/objects)
(export gerbil-ascent-scoped-reachability-mask-program
        gerbil-ascent-bounded-scoped-reachability-mask-program)

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

;;; Compile exact hop layers, shortest distances and all shortest predecessors
;;; into ordinary relations. No callback computes reachability or provenance.
;;; A banned witness must fit the total hop limit. Shortest prefix/suffix
;;; distances decide existence without joining every pair of exact hop layers.
;; : (forall (v scope) (-> [(Tuple v)] [(Pair v v)] [(Pair scope v)] [(Pair scope v)] [(Pair scope v)] Integer Integer Integer Integer Program))
;; : (-> VertexRows EdgeRows ScopedStarts ScopedTargets ScopedBlocked HopLimit InputBudget FactBudget OutputBudget Program)
(def (gerbil-ascent-bounded-scoped-reachability-mask-program vertices edges starts targets blocked hops
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (unless (and (exact-integer? hops) (<= 0 hops 64))
    (error "ASCENT scoped query hop limit must be an integer in [0,64]" hops))
  (let* ((base (gerbil-ascent-scoped-reachability-mask-program
                vertices edges starts targets blocked input-budget fact-budget output-budget))
         (s (gerbil-ascent-variable 's)) (x (gerbil-ascent-variable 'x))
         (t (gerbil-ascent-variable 't)) (k (gerbil-ascent-variable 'k))
         (scope (gerbil-ascent-variable 'scope)) (z (gerbil-ascent-variable 'z))
         (prefix (gerbil-ascent-variable 'prefix)) (suffix (gerbil-ascent-variable 'suffix)))
    (def (a name . terms)
      (gerbil-ascent-atom name (map (lambda (term)
        (if (exact-integer? term) (gerbil-ascent-literal term) term)) terms)))
    (def (rule head . body) (gerbil-ascent-rule (list head) body))
    (gerbil-ascent-program
      (append (.ref base 'relations)
        (map (lambda (name width) (gerbil-ascent-relation name width []))
             '(mask_hop mask_shorter mask_shortest mask_predecessor) '(3 3 3 4)))
      (append
        (list (rule (a 'mask_hop s s 0) (a 'mask_vertex s))
              (rule (a 'mask_reach s t) (a 'mask_hop s t k))
              (rule (a 'mask_shortest s t k) (a 'mask_hop s t k)
                    (gerbil-ascent-negation 'mask_shorter (list s t k))))
        (apply append (map (lambda (n)
          (append
            (list (rule (a 'mask_hop s t n) (a 'mask_hop s x (- n 1))
                        (a 'mask_edge x t) (a 'mask_vertex t))
                  (rule (a 'mask_shorter s t n) (a 'mask_hop s t (- n 1)))
                  (rule (a 'mask_predecessor s x t n) (a 'mask_shortest s t n)
                        (a 'mask_hop s x (- n 1)) (a 'mask_edge x t)))
            (if (= n 1) []
              (list (rule (a 'mask_shorter s t n) (a 'mask_shorter s t (- n 1)))))))
          (iota hops 1)))
        ;; Scope admission remains native; only integer addition is a guard.
        (list (rule (a 'mask_witness scope s z t)
          (a 'mask_start scope s) (a 'mask_target scope t) (a 'mask_blocked scope z)
          (a 'mask_shortest s z prefix) (a 'mask_shortest z t suffix)
          (gerbil-ascent-guard '(prefix suffix) (lambda (p q) (<= (+ p q) hops)))))
        (cdddr (.ref base 'rules)))
      input-budget fact-budget output-budget (.ref base 'source-handles))))
