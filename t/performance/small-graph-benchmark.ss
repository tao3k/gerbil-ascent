;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Research receipt for the complete three-node operator lifecycle. The
;;; timing gate is aspirational, not a CI assertion until matched runs justify
;;; an admitted budget. Expected rows are computed outside every timed phase.
(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-ref benchmark-fixture-contract-pass?
                 testing-benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/program/operator
                 relational-op-source relational-op-union relational-op-join
                 relational-op-project relational-op-fix
                 relational-op-function relational-op-apply
                 relational-op-compile relational-op-fragment
                 relational-op-reference)
        (only-in :gerbil-ascent/program/interface
                 relational-admit relational-solve relational-query-name
                 relational-compose relational-query
                 relational-op-open-retained relational-op-retained-rows
                 relational-op-retained-replace!
                 relational-op-retained-append!))

(def fixture
  (call-with-input-file "t/performance/small-graph/benchmark.ss" read))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid small-graph benchmark fixture"))

(def possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))

(def (mask-edges mask)
  (let loop ((remaining possible) (bit 1) (rows []))
    (if (null? remaining)
      (reverse rows)
      (loop (cdr remaining) (* bit 2)
            (if (zero? (bitwise-and mask bit)) rows
              (cons (car remaining) rows))))))

;;; Independent finite model; it calls neither the operator interpreter nor
;;; the native planner and remains outside each measured thunk.
(def (finite-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each
     (lambda (edge)
       (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t))
     edges)
    (for-each
     (lambda (pivot)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (+ (* 3 from) pivot))
                        (vector-ref matrix (+ (* 3 pivot) to)))
               (vector-set! matrix (+ (* 3 from) to) #t)))
           '(0 1 2)))
        '(0 1 2)))
     '(0 1 2))
    (let (rows [])
      (for-each
       (lambda (from)
         (for-each
          (lambda (to)
            (when (vector-ref matrix (+ (* 3 from) to))
              (set! rows (cons (list from to) rows))))
          '(0 1 2)))
       '(0 1 2))
      rows)))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (member row expected)) actual)))

(def (reachability edge)
  (let (step
        (relational-op-function
         2 (lambda (path)
             (relational-op-project
              (relational-op-join path edge 1 0) '(0 3)))))
    (relational-op-fix
     2 (lambda (path)
         (relational-op-union edge
                              (relational-op-apply step path))))))

(def closure
  (relational-op-function 2 (lambda (edge) (reachability edge))))

(def (check-rows phase rows expected)
  (unless (same-rows? rows expected)
    (error "small-graph benchmark disagrees with finite model"
           phase rows expected)))

(def (measure phase thunk check)
  (let-values (((receipt result body-phase)
                (testing-benchmark-run/result
                 phase fixture thunk `((phase . ,phase)))))
    (check result)
    (displayln "BENCH " phase
               " p50Ns=" (benchmark-fixture-ref receipt 'p50Ns)
               " p95Ns=" (benchmark-fixture-ref receipt 'p95Ns)
               " maxNs=" (benchmark-fixture-ref receipt 'maxNs)
               " targetMet="
               (<= (benchmark-fixture-ref receipt 'p95Ns) 1000000)
               " gcDelta="
               (benchmark-fixture-ref
                (benchmark-fixture-ref receipt 'runtimeStats)
                'memoryDelta))))

(def (run mask)
  (let* ((edges (mask-edges mask))
         (expected (finite-closure edges))
         (graph (reachability (relational-op-source 'edge 2 edges))))
    (displayln "CASE mask=" mask " edges=" (length edges)
               " output=" (length expected))
    (measure 'reference
             (lambda () (relational-op-reference graph))
             (lambda (rows) (check-rows 'reference rows expected)))
    (measure 'compile
             (lambda ()
               (let-values (((program output)
                             (relational-op-compile graph 64 256 512)))
                 (list program output)))
             (lambda (compiled)
               (check-rows
                'compile
                (relational-query-name
                 (relational-solve (relational-admit (car compiled)))
                 (cadr compiled))
                expected)))
    (let-values (((program output)
                  (relational-op-compile graph 64 256 512)))
      (measure 'admit
               (lambda () (relational-admit program))
               (lambda (admission)
                 (check-rows
                  'admit
                  (relational-query-name
                   (relational-solve admission) output)
                  expected)))
      ;; Admission owns a one-shot run; a repeated solve reuses its result.
      ;; Construct a fresh admission per sample to include actual inference.
      (measure 'admit-solve
               (lambda ()
                 (relational-query-name
                  (relational-solve (relational-admit program)) output))
               (lambda (rows) (check-rows 'admit-solve rows expected)))
      ;; Reuse only immutable schema/analysis. Each sample still builds a
      ;; fresh evaluation state and executes the full semi-naive fixpoint.
      (let* ((seed (gerbil-ascent-make-engine program #t))
             (analysis (.ref seed '.analysis))
             (schema (.ref seed '.schema)))
        (measure 'native-core
                 (lambda ()
                   (let* ((run (gerbil-ascent-make-engine
                                program #f analysis schema))
                          (result (run)))
                     ((.ref result 'rows-of) output)))
                 (lambda (rows) (check-rows 'native-core rows expected)))))
    (measure 'fragment
             (lambda ()
               (let* ((fragment (relational-op-fragment graph 'reach))
                      (program
                       (relational-compose (list fragment) 64 256 512)))
                 (relational-query
                  (relational-solve (relational-admit program))
                  fragment 'reach)))
             (lambda (rows) (check-rows 'fragment rows expected)))
    (measure 'retained-open
             (lambda ()
               (relational-op-open-retained closure edges 64 256 512))
             (lambda (retained)
               (check-rows
                'retained-open
                (relational-op-retained-rows retained) expected)))
    ;; Alternate two distinct source states so every sample performs a real
    ;; replacement.  The empty graph uses one edge as its nonempty state.
    (let* ((replacement (if (null? edges) '((0 1)) edges))
           (replacement-rows (finite-closure replacement))
           (retained (relational-op-open-retained closure [] 64 256 512))
           (next-rows replacement))
      (measure 'retained-replace
               (lambda ()
                 (let-values (((old current added removed)
                               (relational-op-retained-replace!
                                retained next-rows)))
                   (let (wanted (if (null? next-rows) [] replacement-rows))
                     (check-rows 'retained-replace current wanted)
                     (set! next-rows (if (null? next-rows) replacement []))
                     current)))
               (lambda (rows) (void))))
    (let* ((grown (cons '(0 1) edges))
           (grown-expected (finite-closure grown))
           (retained (relational-op-open-retained closure grown
                                                 128 256 512)))
      (measure 'retained-duplicate
               (lambda ()
                 (let-values (((old current added)
                               (relational-op-retained-append!
                                retained '(0 1))))
                   current))
               (lambda (rows)
                 (check-rows 'retained-duplicate rows grown-expected))))))

(for-each run '(0 7 63))
