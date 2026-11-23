;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list list-sort)
        (only-in :gerbil-ascent/program/api relational-choice-program
                 relational-choice-solve relational-program-query)
        (only-in :gerbil-ascent/program/scheme-choice call-with-relational-choice-measurement))
(export dusa-representative-test)

;; Figure 3 of Finite-Choice Logic Programming (POPL 2025).
(def (representative-program nodes arcs)
  (relational-choice-program
    (relation node (id) (map list nodes))
    (relation arc (left right) arcs)
    (relation edge (left right))
    (choice representative (node value))
    (rule (edge ?x ?y) (arc ?x ?y))
    (rule (edge ?x ?y) (edge ?y ?x))
    (rule (open (representative ?x) ?x) (node ?x))
    (rule (closed (representative ?y) (?z)) (edge ?x ?y) (representative ?x ?z))
    (limits 4096 8192 8192)))

;; Independent graph oracle. Flood the undirected input, then take the
;; Cartesian product of representative choices from the components.
(def (components nodes arcs)
  (def (neighbors node)
    (filter-map (lambda (arc)
                  (cond ((= node (car arc)) (cadr arc))
                        ((= node (cadr arc)) (car arc))
                        (else #f))) arcs))
  (let next ((nodes nodes) (groups []))
    (if (null? nodes) (reverse groups)
      (let (group
            (let flood ((todo (list (car nodes))) (seen []))
              (cond ((null? todo) seen)
                    ((memv (car todo) seen) (flood (cdr todo) seen))
                    (else (flood (append (neighbors (car todo)) (cdr todo))
                                 (cons (car todo) seen))))))
        (next (filter (lambda (node) (not (memv node group))) nodes)
              (cons group groups))))))

(def (ordered rows)
  (list-sort (lambda (a b) (< (car a) (car b))) rows))

(def (oracle-models groups)
  (if (null? groups) (list [])
    (let (tails (oracle-models (cdr groups)))
      (apply append
             (map (lambda (root)
                    (let (rows (map (lambda (node) (list node root)) (car groups)))
                      (map (lambda (tail) (ordered (append rows tail))) tails)))
                  (car groups))))))

(def (model-rows models)
  (map (lambda (model) (ordered (relational-program-query model 'representative))) models))

(def (model-witnesses models)
  (map (lambda (model) (relational-program-query model 'representative provenance?: #t)) models))

(def (count receipt name) (cdr (assq name receipt)))

(def (path offset width)
  (map (lambda (i) (list i (+ i 1))) (iota (- width 1) offset)))

(def (clique width)
  (apply append (map (lambda (left)
                       (map (lambda (right) (list left right))
                            (iota (- width left 1) (+ left 1))))
                     (iota width))))

(def (measure-graph label nodes arcs)
  (let* ((program (representative-program nodes arcs))
         (expected (oracle-models (components nodes arcs)))
         (full-times []) (delta-times []) (full-work #f) (delta-work #f))
    (def (run rescan?)
      (call-with-relational-choice-measurement
       (lambda () (relational-choice-solve program state-budget: 20000)) rescan?))
    (def (stable-work receipt)
      (filter (lambda (entry) (not (eq? (car entry) 'first-model-ns))) receipt))
    (for-each
     (lambda (repetition)
       (let*-values (((first first-work) (run (even? repetition)))
                     ((second second-work) (run (odd? repetition))))
         (let* ((full? (even? repetition))
                (full (if full? first-work second-work))
                (delta (if full? second-work first-work))
                (rows (model-rows first)))
           (check-equal? (length rows) (length expected))
           (check-equal? (andmap (lambda (want) (and (member want rows) #t)) expected) #t)
           (check-equal? rows (model-rows second))
           (check-equal? (model-witnesses first) (model-witnesses second))
           (check-equal? (count full 'partial-matches) (count delta 'partial-matches))
           (check-equal? (count full 'states) (count delta 'states))
           (check-equal? (count full 'new-offers) (count delta 'new-offers))
           (check-equal? (count delta 'repeated-offers) 0)
           (check (> (count full 'repeated-offers) 0) => #t)
           (check (> (count delta 'extensions) 0) => #t)
           (when full-work
             (check-equal? (stable-work full) full-work)
             (check-equal? (stable-work delta) delta-work))
           (set! full-work (stable-work full))
           (set! delta-work (stable-work delta))
           (set! full-times (cons (count full 'first-model-ns) full-times))
           (set! delta-times (cons (count delta 'first-model-ns) delta-times)))))
     (iota 5))
    (write (list 'DUSA-REPRESENTATIVE label (cons 'vertices (length nodes))
                 (cons 'undirected-edges (length arcs)) (cons 'models (length expected))
                 (cons 'rescan full-work) (cons 'delta delta-work)
                 (cons 'rescan-first-model-ns (reverse full-times))
                 (cons 'delta-first-model-ns (reverse delta-times))))
    (newline)))

(def dusa-representative-test
  (test-suite "Dusa Figure 3 connected-component representatives"
    (test-case "sparse path" (measure-graph 'path (iota 24) (path 0 24)))
    (test-case "dense component" (measure-graph 'clique (iota 12) (clique 12)))
    (test-case "disconnected components with an isolated vertex"
      (measure-graph 'disconnected (iota 11) (append (path 0 5) (path 5 5))))))
