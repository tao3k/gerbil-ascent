;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (prefix-in :clan/poo/testing/property property.)
        (prefix-in :clan/poo/testing/property/generator generator.)
        (prefix-in :clan/poo/testing/property/replay replay.)
        (only-in :clan/poo/testing/property/test require-passed)
        (only-in :gerbil-ascent/program/api relational-choice-solve)
        (only-in :gerbil-ascent/program/scheme-choice call-with-relational-choice-measurement)
        (only-in "../../benchmarks/dusa-representative-test.ss"
                 representative-program components oracle-models model-rows model-witnesses))
(export ascent-choice-property-test)

;; Vary the graph, including orientations, duplicate input occurrences,
;; isolated nodes and nested parent restores in distinct components.
(def graph-generator
  (generator.generator-map
   (generator.generator-sequence
    (list (generator.generator-integer-range 4 7)
          (generator.generator-integer-range 0 3)
          (generator.generator-list
           (generator.generator-sequence
            (list (generator.generator-integer-range 0 7)
                  (generator.generator-integer-range 0 7))) max-length: 12)))
   (lambda (sample)
     (with ([width shape draws] sample)
       (def split (quotient width 2))
       (def backbone
         (case shape
           ((0) [])
           ((1) (map (lambda (i) (list i (+ i 1))) (iota (- width 1))))
           (else
            (filter-map (lambda (i) (and (not (= (+ i 1) split)) (list i (+ i 1))))
                        (iota (- width 1))))))
       (def arcs
         (filter-map
          (lambda (draw)
            (with ([left right] draw)
              (let ((u (modulo left width)) (v (modulo right width)))
                (and (or (< shape 2) (eq? (< u split) (< v split))) (list u v))))) draws))
       (list width (append arcs backbone))))))

(def graph-domain
  (property.make-specification
   (lambda (value)
     (match value
       ([width arcs]
        (and (exact-integer? width) (<= 4 width 7) (list? arcs) (<= (length arcs) 18)
             (andmap (lambda (arc)
                       (match arc
                         ([u v] (and (exact-integer? u) (exact-integer? v)
                                     (<= 0 u (- width 1)) (<= 0 v (- width 1))))
                         (else #f))) arcs)))
       (else #f)))
   (lambda (sample) (with ([width arcs] sample) (+ width (length arcs))))))
(def graph-codec (replay.make-codec '(ascent-choice-graph (vertices 4 7) (max-arcs 18)) values values))

(def (adjacent? arcs a b)
  (or (member (list a b) arcs) (member (list b a) arcs)))

;; Validate the actual derivation independently. At each step, enumerate its
;; supports from the input graph and the already assigned representatives.
;; This detects evidence from a discarded sibling even when its head agrees.
(def (valid-witness? model witness arcs)
  (let loop ((steps witness) (assigned []))
    (match steps
      ([] (and (= (length assigned) (length model))
               (andmap (lambda (row) (and (member row assigned) #t)) model)))
      ([[kind ['representative node value] supports] . more]
       (let (neighbors (filter (lambda (row) (adjacent? arcs (car row) node)) assigned))
         (and (member (list node value) model) (not (assv node assigned))
              (if (null? neighbors)
                (and (eq? kind 'branch) (= node value)
                     (match supports
                       ([[0 'open _ [['node source]] [offered]]] (= source offered node))
                       (else #f)))
                (let (rows
                      (filter-map
                       (lambda (support)
                         (match support
                           ([1 'closed _ [['edge from target] ['representative source prior]] [offered]]
                            (and (= from source) (= target node) (= prior offered value) (list source prior)))
                           (else #f))) supports))
                  (and (eq? kind 'deduction)
                       (= (length rows) (length supports) (length neighbors))
                       (andmap (lambda (row) (and (member row rows) #t)) neighbors))))
              (loop more (cons (list node value) assigned)))))
      (else #f))))

(def (graph-property sample)
  (with ([width arcs] sample)
    (let* ((nodes (iota width)) (program (representative-program nodes arcs))
           (groups (components nodes arcs)) (expected (oracle-models groups)))
      (let*-values
          (((cached work)
            (call-with-relational-choice-measurement
             (lambda () (relational-choice-solve program state-budget: 4096))))
           ((direct direct-work)
            (call-with-relational-choice-measurement
             (lambda () (relational-choice-solve program state-budget: 4096)) 'direct)))
        (let* ((actual (model-rows cached)) (witnesses (model-witnesses cached)))
          (and (= (length actual) (length expected))
               (andmap (lambda (want) (and (member want actual) #t)) expected)
               (equal? actual (model-rows direct))
               (equal? witnesses (model-witnesses direct))
               (= (cdr (assq 'states work)) (cdr (assq 'states direct-work)))
               (<= (cdr (assq 'peak-parent-units work)) 4096)
               (or (not (ormap (lambda (group) (pair? (cdr group))) groups))
                   (> (cdr (assq 'parent-restores work)) 0))
               (andmap (lambda (model witness) (valid-witness? model witness arcs)) actual witnesses)))))))

(def (graph-labels sample)
  (with ([width arcs] sample)
    (let (groups (components (iota width) arcs))
      (filter values
        (list (and (null? arcs) 'edgeless)
              (and (null? (cdr groups)) 'connected)
              (and (pair? (cdr groups)) 'disconnected)
              (and (>= (length (filter (lambda (group) (pair? (cdr group))) groups)) 2) 'nested-alternatives)
              (and (ormap (lambda (group) (null? (cdr group))) groups) 'isolated)
              (and (ormap (lambda (arc) (= (car arc) (cadr arc))) arcs) 'self-loop))))))

(def ascent-choice-property-test
  (test-suite "POO properties for Dusa branch caches and witnesses"
    (test-case "generated graph cuts agree with independent models and witnesses"
      (for-each
       (lambda (seed)
         (let (report
               (property.check-property graph-generator graph-property graph-domain
                 seed: seed cases: 500 size: 12 shrink-budget: 128
                 policy: (property.make-policy name: 'ascent-choice-graph
                           labels: graph-labels
                           required: '((edgeless . 1) (connected . 1) (disconnected . 1)
                                       (nested-alternatives . 1) (isolated . 1) (self-loop . 1)))))
           (displayln "POO-DUSA-PBT " (property.report-diagnostics report))
           (when (eq? (property.report-status report) 'failed)
             (replay.write-counterexample report graph-codec (current-output-port)))
           (require-passed report)
           (check-equal? (property.report-accepted report) 500)
           (check-equal? (property.report-discarded report) 0)))
       '(20261123 20261124)))
    (test-case "two independent edges keep their parent constraints isolated"
      (check-equal? (graph-property '(4 ((0 1) (2 3)))) #t))
    (test-case "an otherwise valid head rejects a sibling's grounded support"
      (let* ((arcs '((0 1) (1 2)))
             (models (relational-choice-solve (representative-program '(0 1 2) arcs) state-budget: 64))
             (rows (model-rows models)) (proofs (model-witnesses models))
             (foreign-root (cadar (cadr rows)))
             (corrupt
              (map (lambda (step)
                     (match step
                       (['deduction assignment [[1 'closed origin [edge ['representative source _]] _] . tail]]
                        (list 'deduction assignment
                              (cons (list 1 'closed origin (list edge (list 'representative source foreign-root))
                                          (list foreign-root))
                                    tail)))
                       (else step)))
                   (car proofs))))
        (check-equal? (valid-witness? (car rows) (car proofs) arcs) #t)
        (check-equal? (valid-witness? (car rows) corrupt arcs) #f)))))
