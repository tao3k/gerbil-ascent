;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/benchmark-api
                 benchmark-fixture-contract-pass?
                 benchmark-fixture-ref
                 benchmark-receipt-pass?
                 benchmark-run/result)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation
                 gerbil-ascent-program
                 gerbil-ascent-evaluate-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-byods-trrel/benchmark.ss" read))
(def edges (map (lambda (from) (list from (+ from 1))) (iota 20)))
(def (program name provider)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation
          name 2 edges gerbil-ascent-hash-index-provider provider))
   [] 32 250 250))

(def tr-program (program 'tr gerbil-ascent-trrel-storage-provider))
(def uf-program (program 'uf gerbil-ascent-trrel-uf-storage-provider))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT BYODS trrel benchmark" fixture))

(def (run-case name program expected-count reflexive?)
  (let-values (((receipt result)
                (benchmark-run/result fixture
                                      (lambda ()
                                        (gerbil-ascent-evaluate-program program)))))
    (let (rows ((.ref result 'rows-of) name))
      (unless (and (= (length rows) expected-count)
                   (member '(0 20) rows)
                   (equal? (not (not (member '(0 0) rows))) reflexive?)
                   (equal? (not (not (member '(20 20) rows))) reflexive?))
        (error "ASCENT BYODS trrel changed closure semantics" name)))
    (unless (benchmark-receipt-pass? receipt)
      (error "ASCENT BYODS trrel exceeded the benchmark budget" name receipt))
    (display "[gerbil-ascent-benchmark] ascent-byods-")
    (display name)
    (display " p95=")
    (display (benchmark-fixture-ref receipt 'elapsed))
    (displayln " semanticEquivalent=#t")
    (force-output)))

(run-case 'tr tr-program 210 #f)
(run-case 'uf uf-program 231 #t)
