;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/component-plan
 (prefix-in :gerbil-ascent/t/performance/component-construction/reference old-))
(export construction-analysis construction-shape construction-old-shape)
;;; Synthetic admitted metadata isolates construction from expression compilation.
(def (construction-analysis successors heads)
 (let ((analysis (make-vector 7 #f)) (rules (make-vector (vector-length successors) [])))
  (unless (null? heads)
   (vector-set! rules 0
    (map (lambda (indices)
     (let ((rule (make-vector 6 #f))
           (outputs (map (lambda (id) (vector (vector id []) [])) indices)))
      (vector-set! rule 2 '(0))
      (vector-set! rule 5 (vector outputs [] 0 #t [])) rule)) heads)))
  (vector-set! analysis 5 rules) (vector-set! analysis 6 successors) analysis))
(defrule (define-shape name id members rules predecessors)
 (def (name components)
  (map (lambda (component)
   (list (id component) (members component) (rules component) (predecessors component))) components)))
(define-shape construction-shape positive-component-id positive-component-members positive-component-rules positive-component-predecessors)
(define-shape construction-old-shape old-positive-component-id old-positive-component-members old-positive-component-rules old-positive-component-predecessors)
