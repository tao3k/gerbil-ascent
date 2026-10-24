;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-var-points-to-fixture
                 ascent-var-points-to-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-var-points-to/benchmark.ss" read))

(def program
  (ascent-var-points-to-program
   '(("v1" "v2"))
   '(("v1" "h1") ("v2" "h2") ("v3" "h3"))
   '(("v4" "v1" "f"))
   '(("v1" "f" "v3"))))

(def (candidate-points-to)
  (gerbil-ascent-evaluate-program program))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT points-to benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result fixture candidate-points-to)))
  (let ((rows-of (.ref result 'rows-of)))
    (unless (and (= (length (rows-of 'alias)) 4)
                 (= (length (rows-of 'points-to)) 5)
                 (member '("v4" "h3") (rows-of 'points-to)))
      (error "ASCENT points-to scenario changed semantics")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT points-to exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-var-points-to p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
