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
                 gerbil-ascent-eqrel-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 ascent
                 gerbil-ascent-relation
                 gerbil-ascent-program
                 gerbil-ascent-evaluate-program))

(def fixture
  (call-with-input-file
   "t/scenarios/performance/ascent-byods-eqrel/benchmark.ss" read))
(def program
  (gerbil-ascent-program
   (list (gerbil-ascent-relation
          'eq 2
          (map (lambda (from) (list from (+ from 1)))
               (iota 20))
          gerbil-ascent-hash-index-provider
          gerbil-ascent-eqrel-storage-provider))
   [] 32 500 500))
(def default-program
  (ascent
   (default-storage gerbil-ascent-eqrel-storage-provider)
   (relation eq (from to)
             (map (lambda (from) (list from (+ from 1))) (iota 20)))
   (bounds 32 500 500)))

(unless (eq? (.ref (car (.ref default-program 'relations))
                   'storage-provider)
             gerbil-ascent-eqrel-storage-provider)
  (error "ASCENT program default changed the benchmark storage Provider"))

(unless (benchmark-fixture-contract-pass? fixture)
  (error "invalid ASCENT BYODS benchmark" fixture))

(def (candidate-eqrel)
  (let (rows ((.ref (gerbil-ascent-evaluate-program program) 'rows-of) 'eq))
    (list (length rows)
          (if (member '(0 20) rows) #t #f)
          (if (member '(20 0) rows) #t #f)
          (if (member '(5 5) rows) #t #f))))

(let-values (((receipt result)
              (benchmark-run/result fixture candidate-eqrel)))
  (unless (equal? result '(441 #t #t #t))
    (error "ASCENT BYODS eqrel changed closure semantics"))
  (unless (benchmark-receipt-pass? receipt)
    (error "ASCENT BYODS eqrel exceeded the benchmark budget" receipt))
  (display "[gerbil-ascent-benchmark] ascent-byods-eqrel p95=")
  (display (benchmark-fixture-ref receipt 'elapsed))
  (displayln " semanticEquivalent=#t")
  (force-output))
