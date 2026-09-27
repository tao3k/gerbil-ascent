;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-product-session-output
                 product-program source-score)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-product-session/benchmark.ss" read))

(def program
  (product-program '((0 1 4) (0 4 1) (1 0 5))
                   '((0 2 2) (1 1 3))))

(def (phase-valid? result first second)
  (let* ((rows-of (.ref result 'rows-of))
         (score (rows-of 'score))
         (copy (rows-of 'copy)))
    (and (= (length score) 2)
         (equal? score copy)
         (member (list 0 first) score)
         (member (list 1 second) score))))

(def (candidate-product-session)
  (let* ((session (gerbil-ascent-open-session program))
         (first (gerbil-ascent-session-run session))
         (first-valid? (phase-valid? first #(4 4) #(1 5))))
    (gerbil-ascent-session-append-source!
     session 'score (source-score '(1 5 0)))
    (gerbil-ascent-session-append-source!
     session 'improve '(0 3 1))
    (let (second (gerbil-ascent-session-run session))
      (and first-valid?
           (phase-valid? second #(4 4) #(5 5))
           (phase-valid? first #(4 4) #(1 5))))))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT product session benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result fixture candidate-product-session)))
  (unless result
    (error "ASCENT product session changed fixed-point semantics"))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT product session exceeded benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-product-session p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
