;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-upstream-examples-fixture
                 ascent-fibonacci-example-program
                 ascent-context-flow-example-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(def fibonacci-fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-upstream-examples/benchmark-fibonacci.ss"
   read))

(def context-flow-fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-upstream-examples/benchmark-context-flow.ss"
   read))

(def fibonacci
  (ascent-fibonacci-example-program (iota 6)))

(def context-flow
  (ascent-context-flow-example-program
   '(("w1" "c1" "w2" "c1")
     ("w2" "c1" "r1" "c1")
     ("r1" "c1" "r2" "c1")
     ("w1" "c2" "w2" "c2")
     ("w2" "c2" "r1" "c2")
     ("r1" "c2" "r2" "c2"))))

(def (candidate-fibonacci)
  (gerbil-ascent-evaluate-program fibonacci))

(def (candidate-context-flow)
  (gerbil-ascent-evaluate-program context-flow))

(unless (and (benchmark-fixture-contract-pass? fibonacci-fixture)
             (benchmark-fixture-contract-pass? context-flow-fixture))
  (error "invalid ASCENT upstream example benchmarks"))

(let-values (((receipt result)
              (benchmark-run/result fibonacci-fixture candidate-fibonacci)))
  (let (rows ((.ref result 'rows-of) 'fib))
    (unless (and (= (length rows) 6) (member '(5 8) rows))
      (error "ASCENT Fibonacci scenario changed semantics")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT Fibonacci exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-fibonacci p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))

(let-values (((receipt result)
              (benchmark-run/result context-flow-fixture
                                    candidate-context-flow)))
  (let ((flow-rows ((.ref result 'rows-of) 'flow))
        (res-rows ((.ref result 'rows-of) 'res)))
    (unless (and (= (length flow-rows) 12)
                 (equal? res-rows '(("ok"))))
      (error "ASCENT context-flow scenario changed semantics")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT context-flow exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-context-flow p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
