;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref)
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-rule-strata)
        (rename-in (only-in :gerbil-ascent/t/performance/strata-preflight/reference-semantics gerbil-ascent-rule-strata)
                   (gerbil-ascent-rule-strata old-strata))
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (rename-in (only-in :gerbil-ascent/t/performance/strata-preflight/reference-evaluate gerbil-ascent-evaluate-program)
                   (gerbil-ascent-evaluate-program old-evaluate)))
(export strata-preflight-plans strata-preflight-outcome strata-preflight-program strata-preflight-solve)
(def (strata-preflight-plans width rules kind)
  (let ((heads (map (lambda (n) (vector (+ n 1) [])) (iota width)))
        (body (map (lambda (n) (vector (if (= n (- width 1)) kind 'atom) (vector 0 []))) (iota width))))
    (map (lambda (_) (vector heads body width 0)) (iota rules))))
(def (strata-preflight-outcome old? plans kinds)
  (with-catch (lambda (failure) (error-message failure))
              (lambda () ((if old? old-strata gerbil-ascent-rule-strata) plans (vector-length kinds) kinds))))
(def (strata-preflight-program width rules)
  (let* ((x (gerbil-ascent-variable 'x))
         (names (map (lambda (n) (string->symbol (string-append "out" (number->string n)))) (iota width)))
         (heads (map (lambda (name) (gerbil-ascent-atom name (list x))) names))
         (body (make-list width (gerbil-ascent-atom 'source (list x)))))
    (gerbil-ascent-program
     (cons (gerbil-ascent-relation 'source 1 '((7)))
           (map (lambda (name) (gerbil-ascent-relation name 1 [])) names))
     (map (lambda (_) (gerbil-ascent-rule heads body)) (iota rules)) 65536 65536 65536)))
(def (strata-preflight-solve old? program cold?)
  ;; A fresh POO declaration identity prevents either side from using cached
  ;; analysis in cold calls. Both wrappers are constructed inside the interval.
  (let* ((input (if cold? (.o (:: @ program)) program))
         (result ((if old? old-evaluate gerbil-ascent-evaluate-program) input)))
    (unless (.ref result 'finished) (error "incomplete strata preflight public solve"))
    (map (lambda (name) ((.ref result 'rows-of) name)) (.ref result 'relation-names))))
