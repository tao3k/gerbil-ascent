;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-positive-program-fixture
                 ascent-positive-fixture-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-positive-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-positive-clauses/benchmark.ss" read))

(def source '((1 2 "a") (2 3 "b") (3 3 "c")))
(def program (ascent-positive-fixture-program source))

(def (candidate-clauses)
  (gerbil-ascent-evaluate-positive-program program))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT positive-clause benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result fixture candidate-clauses)))
  (let (rows-of (.ref result 'rows-of))
    (unless (and (= (length (rows-of 'hot)) 1)
                 (= (length (rows-of 'choice)) 6)
                 (= (length (rows-of 'generated)) 3)
                 (= (length (rows-of 'reach)) 4))
      (error "ASCENT positive clauses changed the expected relations")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT positive clauses exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-positive-clauses p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
