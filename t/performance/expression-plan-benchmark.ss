;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import
  (only-in :asp-gerbil-scheme/benchmark-api
    benchmark-fixture-ref benchmark-fixture-contract-pass? benchmark-run/result)
  (only-in :gerbil/expander core-resolve-library-module-path)
  (only-in :clan/poo/object .ref)
  (only-in :gerbil-ascent/t/performance/expression-plan/input expression-program)
  (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
  (rename-in (only-in :gerbil-ascent/t/performance/expression-plan/evaluate-reference
    gerbil-ascent-evaluate-program) (gerbil-ascent-evaluate-program old-evaluate)))
(export main)

(def (result-rows result)
  (map (lambda (name) (cons name ((.ref result 'rows-of) name)))
       (.ref result 'relation-names)))

(def (project result)
  (list (.ref result 'finished)
        (map (lambda (entry) (cons (car entry) (cdr entry))) (result-rows result))))

(def (integer-power base count)
  (let loop ((left count) (value 1))
    (if (zero? left) value (loop (- left 1) (* value base)))))

(def (check-result a b width stages expressions? scope)
  (unless (equal? (project a) (project b)) (error "ordered solve results differ"))
  (let* ((name (string->symbol (string-append "v" (number->string stages))))
         (rows (cdr (assq name (result-rows b))))
         (expected (map (lambda (x)
                          (list (if expressions?
                                  (let* ((c (+ scope 1)) (power (integer-power c stages)))
                                    (+ (* power x) (/ (* c (- power 1)) (- c 1)))) x)))
                        (iota width))))
    (unless (and (.ref b 'finished) (= (length rows) width)
                 (andmap (lambda (row) (and (member row rows) #t)) expected))
      (error "independent expression truth differs"))))

(def (median xs)
  (list-ref (list-sort < xs) (quotient (length xs) 2)))

(def (measure call)
  (##gc)
  (let* ((before (##process-statistics))
         (result (call))
         (after (##process-statistics))
         (bytes (- (f64vector-ref after 7) (f64vector-ref before 7)
                   (f64vector-ref after 9)))
         (cpu (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                 (+ (f64vector-ref before 0) (f64vector-ref before 1)))))
    (unless (>= bytes 0) (error "invalid cumulative allocation counter"))
    (values result bytes cpu)))

(def (main scenario library receipt-path)
  (add-load-path! library)
  (def contract
    (call-with-input-file "t/performance/expression-plan/benchmark.ss" read))
  (unless (benchmark-fixture-contract-pass? contract)
    (error "invalid expression plan fixture"))
  (def entry
    (assq (string->symbol scenario)
          (benchmark-fixture-ref contract 'scenarios)))
  (unless entry (error "unknown expression plan scenario" scenario))
  (for-each
    (lambda (name)
      (unless
        (equal?
          (core-resolve-library-module-path
            (string->symbol (string-append ":gerbil-ascent/" name)))
          (path-expand (string-append "gerbil-ascent/" name ".ssi") library))
        (error "expression plan module mismatch" name)))
    '("program/evaluate" "core/positive-plan" "t/performance/expression-plan/evaluate-reference" "t/performance/expression-plan/reference"))
  (let* ((config (cdr entry))
         (get (lambda (key) (benchmark-fixture-ref config key)))
         (ab []) (bb []) (ac []) (bc []) (wins 0) (count 0))
    (let* ((width (get 'width)) (stages (get 'stages))
           (expressions? (get 'expressions)) (scope (get 'scope))
           (program (expression-program width stages expressions? scope)))
      ;; Warm each independent analysis cache. Every timed sample still builds
      ;; a fresh engine, admits source rows and runs the whole fixed point.
      (check-result (old-evaluate program) (gerbil-ascent-evaluate-program program)
                    width stages expressions? scope)
      (def (old-call) (old-evaluate program))
      (def (new-call) (gerbil-ascent-evaluate-program program))
      (def (sample)
        (let-values (((a x u b y v)
                      (if (even? count)
                        (let-values (((a x u) (measure old-call))
                                     ((b y v) (measure new-call)))
                          (values a x u b y v))
                        (let-values (((b y v) (measure new-call))
                                     ((a x u) (measure old-call)))
                          (values a x u b y v)))))
          (check-result a b width stages expressions? scope)
          (set! ab (cons x ab))
          (set! bb (cons y bb))
          (set! ac (cons u ac))
          (set! bc (cons v bc))
          (when (< v u) (set! wins (+ wins 1))))
        (set! count (+ count 1))
        (displayln "EXPRESSION-PAIRS " scenario " " count "/50")
        (force-output)
        count)
      (let-values (((api-receipt selected)
                    (benchmark-run/result contract sample)))
        (let* ((x (median ab)) (y (median bb))
               (a (median ac)) (b (median bc))
               (pass? (and (<= y (+ x (get 'allocationOverheadBytes)))
                           (<= b (+ (* a (get 'cpuRatio))
                                    (get 'cpuOverheadSeconds)))
                           (>= wins (get 'minimumCpuWins)))))
          (call-with-output-file receipt-path
            (lambda (port)
              (write
                (list (cons 'scenario scenario) (cons 'passed? pass?)
                      (cons 'asp-receipt api-receipt) (cons 'cpu-wins wins)
                      (cons 'old-bytes x) (cons 'new-bytes y)
                      (cons 'old-cpu-us (* a 1000000))
                      (cons 'new-cpu-us (* b 1000000))
                      (cons 'old-allocation ab) (cons 'new-allocation bb)
                      (cons 'old-cpu ac) (cons 'new-cpu bc))
                port)))
          (displayln "RESULT " scenario " " pass?
                     " CPU-us " (* a 1000000) " -> " (* b 1000000)
                     " bytes " x " -> " y " wins " wins)
          (force-output)
          (unless pass? (error "expression plan performance gate failed" scenario)))))))
