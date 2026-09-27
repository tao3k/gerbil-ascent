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
                 ascent gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-run))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-nonpositive-session-update/benchmark.ss"
   read))

(def program
  (ascent
   (relation edge (from to) '((0 1) (1 2)))
   (relation blocked (node))
   (relation path (from to))
   (relation safe (from to))
   ((path from to) <-- (edge from to))
   ((path from to) <-- (path from via) (edge via to))
   ((safe from to) <-- (path from to) (not (blocked to)))
   (bounds 8 32 64)))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT nonpositive update benchmark" fixture))

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
                      session 'blocked '(2))
                     (gerbil-ascent-session-run session))))))
    (unless (null? sessions)
      (error "ASCENT nonpositive update did not consume every sample"))
    (for-each
     (lambda (session)
       (let* ((rows-of
               (.ref (gerbil-ascent-session-run session) 'rows-of))
              (path (rows-of 'path))
              (safe (rows-of 'safe)))
         (unless (and (= (length path) 3)
                      (= (length safe) 1)
                      (member '(0 1) safe)
                      (not (member '(0 2) safe)))
           (error "ASCENT nonpositive update changed fixed-point semantics"))))
     prepared)
    (unless (benchmark-receipt-pass? receipt)
      (error "ASCENT nonpositive update exceeded the benchmark budget"
             receipt))
    (display "[gerbil-ascent-benchmark] ascent-nonpositive-session-update p95=")
    (display (benchmark-fixture-ref receipt 'elapsed))
    (displayln " semanticEquivalent=#t")
    (force-output)))
