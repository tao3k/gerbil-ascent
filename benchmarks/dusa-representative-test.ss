;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :gerbil/runtime/gambit
        (only-in :std/list/list list-sort)
        (only-in :gerbil-ascent/program/api relational-choice-program
                 relational-choice-solve relational-program-query)
        (only-in :gerbil-ascent/program/scheme-choice call-with-relational-choice-measurement))
(export dusa-representative-test dusa-parent-representative-test
        representative-program components oracle-models model-rows model-witnesses)

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

(def (observe-solve run)
  (let* ((bytes (make-f64vector 2 0.))
         (sampling-start (current-jiffy))
         (before (##process-statistics))
         (_ (##get-bytes-allocated! bytes 0))
         (cpu-start (cpu-time)) (start (current-jiffy)))
    (let-values (((models work) (run)))
      (let* ((end (current-jiffy)) (cpu-end (cpu-time))
             (_ (##get-bytes-allocated! bytes 1))
             (after (##process-statistics)) (sampling-end (current-jiffy))
             (frequency (jiffies-per-second))
             (wall-ns (quotient (* 1000000000 (- end start)) frequency))
             (probe-ns (quotient (* 1000000000 (+ (- start sampling-start)
                                                   (- sampling-end end))) frequency))
             (collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
             (gc-ns (* 1000000000. (- (f64vector-ref after 5) (f64vector-ref before 5))))
             (gc-cpu-ns (* 1000000000. (+ (- (f64vector-ref after 3) (f64vector-ref before 3))
                                          (- (f64vector-ref after 4) (f64vector-ref before 4)))))
             (allocated (- (f64vector-ref bytes 1) (f64vector-ref bytes 0))))
        (values models work
          (list (cons 'wall-ns wall-ns) (cons 'cpu-ns (* 1000000000. (- cpu-end cpu-start)))
                (cons 'collections collections) (cons 'gc-wall-ns gc-ns) (cons 'gc-cpu-ns gc-cpu-ns)
                (cons 'sampling-wall-ns probe-ns)
                (cons 'allocated-bytes (and (zero? collections) (>= allocated 0) allocated))))))))

(def (measure-graph label nodes arcs (restore-parent? #f))
  (let* ((program (representative-program nodes arcs))
         (expected (oracle-models (components nodes arcs)))
         (ordered-rows #f) (ordered-witnesses #f))
    (def (run reference?)
      (call-with-relational-choice-measurement
       (lambda () (relational-choice-solve program state-budget: 20000))
       (if restore-parent? (and reference? 'direct) (if reference? #t 'direct))))
    (def (measure-lane reference?)
      (let ((first-times []) (totals []) (receipts []) (prior-work #f))
        (for-each
         (lambda (_)
           (let-values (((models work phases) (observe-solve (cut run reference?))))
             (let ((rows (model-rows models)) (witnesses (model-witnesses models))
                   (stable (filter (lambda (entry) (not (memq (car entry) '(first-model-ns total-ns)))) work)))
               (check-equal? (length rows) (length expected))
               (check-equal? (andmap (lambda (want) (and (member want rows) #t)) expected) #t)
               (if ordered-rows
                 (begin
                   (check-equal? rows ordered-rows)
                   (check-equal? witnesses ordered-witnesses))
                 (begin (set! ordered-rows rows) (set! ordered-witnesses witnesses)))
               (when prior-work (check-equal? stable prior-work))
               (set! prior-work stable)
               (set! first-times (cons (count work 'first-model-ns) first-times))
               (set! totals (cons (count work 'total-ns) totals))
               (set! receipts (cons phases receipts)))))
         (iota 5))
        (values prior-work (reverse! first-times) (reverse! totals) (reverse! receipts))))
    ;; Measure all production solves before the more allocation-heavy
    ;; reference for this fixture. The reference still checks every result.
    (let*-values (((delta delta-times delta-total delta-phases) (measure-lane #f))
                  ((full full-times full-total full-phases) (measure-lane #t)))
      (check-equal? (count full 'states) (count delta 'states))
      (check-equal? (count delta 'repeated-offers) 0)
      (check (> (count delta 'extensions) 0) => #t)
      (if restore-parent?
        (begin
          (check (< (count delta 'source-replacements) (count full 'source-replacements)) => #t)
          (check (< (count delta 'partial-matches) (count full 'partial-matches)) => #t)
          (check (> (count delta 'parent-restores) 0) => #t))
        (begin
          (check-equal? (count full 'partial-matches) (count delta 'partial-matches))
          (check-equal? (count full 'new-offers) (count delta 'new-offers))
          (check (> (count full 'repeated-offers) 0) => #t)))
      (write (list (if restore-parent? 'DUSA-PARENT 'DUSA-REPRESENTATIVE) label
                   (cons 'vertices (length nodes)) (cons 'undirected-edges (length arcs))
                   (cons 'models (length expected)) (cons 'rescan full) (cons 'delta delta)
                   (cons 'rescan-first-model-ns full-times) (cons 'delta-first-model-ns delta-times)
                   (cons 'rescan-total-ns full-total) (cons 'delta-total-ns delta-total)
                   (cons 'rescan-samples full-phases) (cons 'delta-samples delta-phases)))
      (newline))))

(def dusa-representative-test
  (test-suite "Dusa Figure 3 connected-component representatives"
    (test-case "sparse path" (measure-graph 'path (iota 24) (path 0 24)))
    (test-case "dense component" (measure-graph 'clique (iota 12) (clique 12)))
    (test-case "disconnected components with an isolated vertex"
      (measure-graph 'disconnected (iota 11) (append (path 0 5) (path 5 5))))))

(def dusa-parent-representative-test
  (test-suite "Dusa Figure 3 with completed parent restore"
    (test-case "48-vertex path" (measure-graph 'path (iota 48) (path 0 48) #t))
    (test-case "22-vertex dense component" (measure-graph 'clique (iota 22) (clique 22) #t))
    (test-case "two nine-vertex components and an isolated vertex"
      (measure-graph 'disconnected (iota 19) (append (path 0 9) (path 9 9)) #t))))
