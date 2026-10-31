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
(def ring-edges
  '((0 1) (1 2) (2 3) (3 4)
    (4 5) (5 6) (6 7) (7 0)
    (0 4) (2 6) (4 0) (6 2)))
(def (program name provider source)
  (gerbil-ascent-program
   (list (gerbil-ascent-relation
          name 2 source gerbil-ascent-hash-index-provider provider))
   [] 32 250 250))

(def tr-program (program 'tr gerbil-ascent-trrel-storage-provider edges))
(def uf-program (program 'uf gerbil-ascent-trrel-uf-storage-provider edges))
(def tr-ring-program
  (program 'tr-ring gerbil-ascent-trrel-storage-provider ring-edges))
(def uf-ring-program
  (program 'uf-ring gerbil-ascent-trrel-uf-storage-provider ring-edges))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT BYODS trrel benchmark" fixture))

(def (run-case name program expected-count end reflexive?)
  (let-values (((receipt result)
                (benchmark-run/result fixture
                                      (lambda ()
                                        (gerbil-ascent-evaluate-program program)))))
    (let (rows ((.ref result 'rows-of) name))
      (unless (and (= (length rows) expected-count)
                   (member (list 0 end) rows)
                   (equal? (not (not (member '(0 0) rows))) reflexive?)
                   (equal? (not (not (member (list end end) rows)))
                           reflexive?))
        (error "ASCENT BYODS trrel changed closure semantics" name)))
    (unless (benchmark-receipt-pass? receipt)
      (error "ASCENT BYODS trrel exceeded the benchmark budget" name receipt))
    (display "[gerbil-ascent-benchmark] ascent-byods-")
    (display name)
    (display " p95=")
    (display (benchmark-fixture-ref receipt 'elapsed))
    (displayln " semanticEquivalent=#t")
    (force-output)))

(run-case 'tr tr-program 210 20 #f)
(run-case 'uf uf-program 231 20 #t)
(run-case 'tr-ring tr-ring-program 56 7 #f)
(run-case 'uf-ring uf-ring-program 64 7 #t)
