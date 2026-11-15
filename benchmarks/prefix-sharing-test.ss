;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list append-map)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/scheme-language relational-program)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/core/positive-plan current-positive-prefix-budget
                 make-positive-plan-cost call-with-positive-plan-cost positive-plan-cost-snapshot))
(export prefix-sharing-test)

(def (prefix-workload nodes fanout focus)
  (let ((edges (append-map
                (lambda (from)
                  (map (lambda (offset) (list from (modulo (+ from offset) nodes)))
                       (iota fanout)))
                (iota nodes)))
        (labels (map (lambda (id) (list id (modulo (+ id 1) nodes))) (iota nodes)))
        (seeds (map list focus)))
    (relational-program
      (relation edge (from middle) edges)
      (relation label (middle to) labels)
      (relation seed (to) seeds)
      (relation target (to))
      (relation left (from to))
      (relation right (from to))
      (rule (target ?z) (seed ?z))
      (rule (left ?x ?z) (edge ?x ?y) (label ?y ?z) (target ?z))
      (rule (right ?x ?z) (edge ?x ?y) (label ?y ?z) (target ?z))
      (limits 40000 10000 60000))))

(def (row-order? a b)
  (or (< (car a) (car b))
      (and (= (car a) (car b)) (< (cadr a) (cadr b)))))

(def (prefix-answers result)
  (check-equal? (.ref result 'finished) #t)
  (let (rows-of (.ref result 'rows-of))
    (list (rows-of 'left) (rows-of 'right))))

(def (observe-prefixes program nodes fanout budget expected)
  (def (run)
    (parameterize ((current-positive-prefix-budget budget))
      (gerbil-ascent-evaluate-program program)))
  ;; Keep the work collector and forced collections out of the CPU interval.
  (##gc)
  (let* ((before (##process-statistics))
         (allocation (make-f64vector 2 0.))
         (_ (##get-bytes-allocated! allocation 0))
         (started (cpu-time))
         (result (run))
         (cpu-us (* 1000000. (- (cpu-time) started)))
         (_ (##get-bytes-allocated! allocation 1))
         (after-run (##process-statistics)))
    (let* ((collections (- (f64vector-ref after-run 6) (f64vector-ref before 6)))
           (bytes (- (f64vector-ref allocation 1) (f64vector-ref allocation 0)))
           (cost (make-positive-plan-cost #f #f))
           (counted (call-with-positive-plan-cost cost run))
           (work (positive-plan-cost-snapshot cost))
           (answers (prefix-answers result)))
      (for-each (lambda (rows) (check-equal? (list-sort row-order? rows) expected)) answers)
      (check-equal? (prefix-answers counted) answers)
      (display "PREFIX-SHARING ")
      (write
       (append (list (cons 'nodes nodes) (cons 'fanout fanout) (cons 'budget budget)
                     (cons 'cpu-us cpu-us)
                     (cons 'allocation-counter-delta (and (zero? collections) (>= bytes 0) bytes))
                     (cons 'collections collections))
               (map (cut assq <> work)
                    '(prefix-state-tests prefix-build-input-rows prefix-slot-stores
                      prefix-state-replays prefix-slot-restores candidate-rows
                      physical-index-probes complete-witnesses))))
      (newline)
      (values answers work))))

(def (compare-prefixes nodes fanout)
  (let* ((focus (map (lambda (id) (* id (quotient nodes 128))) (iota 128)))
         (program (prefix-workload nodes fanout focus))
         ;; Inverse mapping computes the answers without rule evaluation or
         ;; caches. Each label has one predecessor per edge offset.
         (expected (list-sort row-order?
                     (append-map (lambda (target)
                       (map (lambda (offset)
                              (list (modulo (- target 1 offset) nodes) target))
                            (iota fanout))) focus))))
    (let-values (((ordinary ordinary-work) (observe-prefixes program nodes fanout 0 expected))
                 ((tight tight-work) (observe-prefixes program nodes fanout 32 expected))
                 ((shared shared-work) (observe-prefixes program nodes fanout 262144 expected)))
      (check-equal? tight ordinary)
      (check-equal? shared ordinary)
      (check-equal? (cdr (assq 'prefix-state-tests ordinary-work)) 0)
      (check (> (cdr (assq 'prefix-state-tests tight-work)) 0) => #t)
      (check (> (cdr (assq 'prefix-state-replays shared-work)) 0) => #t)
      (check-equal? (cdr (assq 'complete-witnesses shared-work))
                    (cdr (assq 'complete-witnesses ordinary-work))))))

(def prefix-sharing-test
  (test-suite "Ordered shared prefixes at a published delta"
    (test-case "sparse chain with 16384 edges and 128 selected targets"
      (compare-prefixes 16384 1))
    (test-case "16-way graph with 16384 edges and 128 selected targets"
      (compare-prefixes 1024 16))))
