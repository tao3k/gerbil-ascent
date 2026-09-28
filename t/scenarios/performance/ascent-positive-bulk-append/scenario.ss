;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-program
                 gerbil-ascent-open-session gerbil-ascent-session-run
                 gerbil-ascent-session-append-source!))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-positive-bulk-append/benchmark.ss" read))
(def size 10000)
(def program
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'item 1 [])) [] size size size))

(def (candidate-bulk-append)
  (let (session (gerbil-ascent-open-session program))
    (gerbil-ascent-session-run session)
    (for-each
     (lambda (value)
       (gerbil-ascent-session-append-source! session 'item (list value)))
     (iota size))
    ((.ref (gerbil-ascent-session-run session) 'rows-of) 'item)))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT positive bulk append benchmark" fixture))

(let-values (((receipt count)
              (benchmark-run/result
               fixture (lambda () (length (candidate-bulk-append))))))
  (unless (= count size)
    (error "ASCENT bulk append changed source row count" count))
  (unless (equal? (candidate-bulk-append) (map list (iota size)))
    (error "ASCENT bulk append changed source rows"))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT positive bulk append exceeded benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-positive-bulk-append p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
