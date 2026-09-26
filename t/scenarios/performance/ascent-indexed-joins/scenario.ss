;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-indexed-joins/benchmark.ss" read))
(def program (ascent-index-fixture-program))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT indexed-join benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result fixture
                                    (lambda ()
                                      (gerbil-ascent-evaluate-program program)))))
  (let (rows ((.ref result 'rows-of) 'two-hop))
    (unless (and (= (length rows) 49)
                 (member '(0 2) rows)
                 (member '(48 50) rows)
                 (not (member '(0 3) rows)))
      (error "ASCENT indexed join changed two-hop semantics")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT indexed joins exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-indexed-joins p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
