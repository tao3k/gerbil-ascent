;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-mutual-program-fixture
                 ascent-mutual-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-mutual-recursive-heads/benchmark.ss" read))

(def program (ascent-mutual-program '((1 2) (2 3) (3 1))))
(def expected-pairs
  '((1 1) (1 2) (1 3)
    (2 1) (2 2) (2 3)
    (3 1) (3 2) (3 3)))

(def (candidate-recursive-heads)
  (gerbil-ascent-evaluate-program program))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT recursive-head benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result fixture candidate-recursive-heads)))
  (let (rows-of (.ref result 'rows-of))
    (unless (and (let (rows (rows-of 'path0))
                   (and (= (length rows) 9)
                        (andmap (lambda (row) (member row rows))
                                expected-pairs)))
                 (let (rows (rows-of 'path1))
                   (and (= (length rows) 9)
                        (andmap (lambda (row) (member row rows))
                                expected-pairs)))
                 (let (rows (rows-of 'witness))
                   (and (= (length rows) 3)
                        (andmap (lambda (row) (member row rows))
                                '((1) (2) (3))))))
      (error "ASCENT recursive-head relations changed")))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT recursive-heads exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-mutual-recursive-heads p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
