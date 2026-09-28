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
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-ten-thousand-appends/benchmark.ss" read))
(def rows (map list (iota 10000)))
(def program
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'item 1 [])) [] 10002 10000 10000))
(def last-result #f)

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT ten-thousand-append benchmark" fixture))

(let-values (((receipt result)
              (benchmark-run/result
               fixture
               (lambda ()
                 (let (session (gerbil-ascent-open-session program))
                   (gerbil-ascent-session-run session)
                   (for-each
                    (lambda (row)
                      (gerbil-ascent-session-append-source!
                       session 'item row))
                    rows)
                   (set! last-result
                     (gerbil-ascent-session-run session))
                   #t)))))
  (unless (eq? result #t)
    (error "ASCENT ten-thousand-append result changed"))
  (unless (equal? ((.ref last-result 'rows-of) 'item) rows)
    (error "ASCENT ten-thousand-append output changed"))
  (display "[gerbil-ascent-benchmark] ascent-ten-thousand-appends p95=")
  (displayln (benchmark-fixture-ref receipt 'elapsed))
  (displayln
   (list 'p50-ns (benchmark-fixture-ref receipt 'p50Ns)
         'p95-ns (benchmark-fixture-ref receipt 'p95Ns)
         'max-ns (benchmark-fixture-ref receipt 'maxNs)
         'over-50ms
         (length (filter (lambda (ns) (> ns 50000000))
                         (benchmark-fixture-ref receipt 'samplesNs)))))
  (force-output)
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT ten-thousand-append latency exceeded the unchanged 50 ms bound")))
