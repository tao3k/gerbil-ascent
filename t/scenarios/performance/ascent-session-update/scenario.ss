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
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-session-update/benchmark.ss" read))

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))

(def program
  (gerbil-ascent-program
   (list (gerbil-ascent-relation
          'edge 2 (map (lambda (from) (list from (+ from 1)))
                       (iota 10)))
         (gerbil-ascent-relation 'reach 2 []))
   (list (gerbil-ascent-rule
          (list (a 'reach (v 'x) (v 'y)))
          (list (a 'edge (v 'x) (v 'y))))
         (gerbil-ascent-rule
          (list (a 'reach (v 'x) (v 'z)))
          (list (a 'reach (v 'x) (v 'y))
                (a 'edge (v 'y) (v 'z)))))
   16 128 160))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT session update benchmark" fixture))

;; Prepare sessions before timing so each sample measures an actual update.
(let* ((prepared (map (lambda (_)
                        (let (session (gerbil-ascent-open-session program))
                          (gerbil-ascent-session-run session)
                          session))
                      (iota (benchmark-fixture-ref fixture 'sampleCount))))
       (sessions prepared))
  (let-values (((receipt result)
                (benchmark-run/result
                 fixture
                 (lambda ()
                   (let (session (car sessions))
                     (set! sessions (cdr sessions))
                     (gerbil-ascent-session-append-source!
                      session 'edge '(10 11))
                     (gerbil-ascent-session-run session))))))
    (unless (null? sessions)
      (error "ASCENT session update did not consume every sample"))
    (for-each
     (lambda (session)
       (let (rows ((.ref (gerbil-ascent-session-run session) 'rows-of)
                   'reach))
         (unless (and (= (length rows) 66)
                      (member '(0 11) rows)
                      (member '(10 11) rows))
           (error "ASCENT session update changed closure semantics"))))
     prepared)
    (unless (benchmark-receipt-pass? receipt)
      (error "ASCENT session update exceeded the benchmark budget" receipt))
    (display "[gerbil-ascent-benchmark] ascent-session-update p95=")
    (display (benchmark-fixture-ref receipt 'elapsed))
    (displayln " semanticEquivalent=#t")
    (force-output)))
