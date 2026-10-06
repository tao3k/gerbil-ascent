;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import
  (only-in :asp-gerbil-scheme/benchmark-api
    benchmark-fixture-ref benchmark-fixture-contract-pass? benchmark-run/result)
  (only-in :gerbil/expander core-resolve-library-module-path)
  (only-in :gerbil-ascent/t/performance/proof-replay/input proof-input)
  (only-in :gerbil-ascent/candidate/provenance
    candidate-positive-proof candidate-verify-positive-proof
    positive-proof-status positive-proof-nodes positive-proof-roots
    proof-node-id proof-node-kind proof-node-relation proof-node-row
    proof-node-label proof-node-inputs)
  (rename-in
    (only-in :gerbil-ascent/t/performance/proof-replay/reference
      candidate-positive-proof candidate-verify-positive-proof
      positive-proof-status positive-proof-nodes positive-proof-roots
      proof-node-id proof-node-kind proof-node-relation proof-node-row
      proof-node-label proof-node-inputs)
    (candidate-positive-proof old-candidate-positive-proof)
    (candidate-verify-positive-proof old-candidate-verify-positive-proof)
    (positive-proof-status old-positive-proof-status)
    (positive-proof-nodes old-positive-proof-nodes)
    (positive-proof-roots old-positive-proof-roots)
    (proof-node-id old-proof-node-id)
    (proof-node-kind old-proof-node-kind)
    (proof-node-relation old-proof-node-relation)
    (proof-node-row old-proof-node-row)
    (proof-node-label old-proof-node-label)
    (proof-node-inputs old-proof-node-inputs)))
(export main)

(def (project proof status nodes roots id kind relation row label inputs)
  (list (status proof) (roots proof)
    (map (lambda (node)
           (list (id node) (kind node) (relation node) (row node)
                 (label node) (inputs node)))
         (nodes proof))))

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
    (call-with-input-file "t/performance/proof-replay/benchmark.ss" read))
  (unless (benchmark-fixture-contract-pass? contract)
    (error "invalid proof replay fixture"))
  (def entry
    (assq (string->symbol scenario)
          (benchmark-fixture-ref contract 'scenarios)))
  (unless entry (error "unknown proof replay scenario" scenario))
  (for-each
    (lambda (name)
      (unless
        (equal?
          (core-resolve-library-module-path
            (string->symbol (string-append ":gerbil-ascent/" name)))
          (path-expand (string-append "gerbil-ascent/" name ".ssi") library))
        (error "proof replay module mismatch" name)))
    '("candidate/provenance" "t/performance/proof-replay/reference"))
  (let* ((config (cdr entry))
         (get (lambda (key) (benchmark-fixture-ref config key)))
         (ab []) (bb []) (ac []) (bc []) (wins 0) (count 0))
    (let-values (((input program expected)
                  (proof-input (get 'width) (get 'rules))))
      (def (run produce verify)
        (let (proof (produce input program 'digest 'complete expected 100000))
          (unless (verify input program 'digest 'complete expected proof 5120)
            (error "independent proof replay failed"))
          proof))
      (def (old-call)
        (run old-candidate-positive-proof old-candidate-verify-positive-proof))
      (def (new-call)
        (run candidate-positive-proof candidate-verify-positive-proof))
      (def (sample)
        (let-values (((a x u b y v)
                      (if (even? count)
                        (let-values (((a x u) (measure old-call))
                                     ((b y v) (measure new-call)))
                          (values a x u b y v))
                        (let-values (((b y v) (measure new-call))
                                     ((a x u) (measure old-call)))
                          (values a x u b y v)))))
          (let ((pa (project a old-positive-proof-status old-positive-proof-nodes
                       old-positive-proof-roots old-proof-node-id old-proof-node-kind
                       old-proof-node-relation old-proof-node-row old-proof-node-label
                       old-proof-node-inputs))
                (pb (project b positive-proof-status positive-proof-nodes
                       positive-proof-roots proof-node-id proof-node-kind
                       proof-node-relation proof-node-row proof-node-label
                       proof-node-inputs)))
            (unless
              (and (equal? pa pb) (eq? (car pb) 'complete)
                   (= (length (caddr pb))
                      (* (get 'width) (if (zero? (get 'rules)) 1 2)))
                   (equal? (cadr pb)
                           (iota (get 'width)
                                 (if (zero? (get 'rules)) 0 (get 'width)))))
              (error "proof data or independent node/target count differs")))
          (set! ab (cons x ab))
          (set! bb (cons y bb))
          (set! ac (cons u ac))
          (set! bc (cons v bc))
          (when (< v u) (set! wins (+ wins 1))))
        (set! count (+ count 1))
        (displayln "PROOF-PAIRS " scenario " " count "/50")
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
          (unless pass? (error "proof replay performance gate failed" scenario)))))))
