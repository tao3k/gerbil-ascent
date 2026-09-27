;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-aggregate-program-fixture
                 ascent-derived-aggregate-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-derived-aggregate/benchmark.ss" read))
(def program
  (ascent-derived-aggregate-program
   '((0 1) (1 2) (2 0)) '(0 1 2 5)))

(def (candidate-derived-aggregate)
  (gerbil-ascent-evaluate-program program))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT derived-aggregate benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result fixture candidate-derived-aggregate)))
  (let* ((rows-of (.ref result 'rows-of))
         (paths (rows-of 'path))
         (counts (rows-of 'reach-count)))
    (unless (and (= (length paths) 9)
                 (= (length counts) 4)
                 (andmap (lambda (row) (member row counts))
                         '((0 3) (1 3) (2 3) (5 0))))
      (error "ASCENT derived aggregate changed closure semantics")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT derived aggregate exceeded benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-derived-aggregate p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
