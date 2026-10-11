;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :gerbil-ascent/program/objects
        :gerbil-ascent/t/performance/storage-round/fixture
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/storage-round/reference-evaluate old-)
        (only-in :gerbil-ascent/table/interface gerbil-ascent-set-storage-provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage make-storage-readiness
                 gerbil-ascent-storage-engine-state gerbil-ascent-storage-engine-extension
                 gerbil-ascent-storage-check-state! gerbil-ascent-storage-admit-state!
                 gerbil-ascent-storage-check-readiness! gerbil-ascent-storage-admit-readiness!))
(export ascent-storage-round-test)
;;; Exercise the private source syntax from its exact production owner.
(include "../../program/initialization.ss")
(def (run engine) ((.ref engine '.run)))
(def ascent-storage-round-test
  (test-suite "Custom storage round and readiness ownership"
    (test-case "source admission syntax preserves callback order and budget boundary"
      (let ((events []) (rows '((1) (2))))
        (source-admission-loop callbacks rows
          (row (lambda (r) (set! events (cons (list 'check r) events))))
          (set! events (cons (list 'admit row) events)))
        (check-equal? (reverse events) '((check (1)) (admit (1)) (check (2)) (admit (2)))))
      (let ((events []) (rows '((1) (2))) (count 0))
        (check-exception
          (source-admission-loop pure rows (row 'input 1 count 1 10)
            (set! events (cons row events))) true)
        (check-equal? events '((1)))))
    (test-case "eight complete engines match independent result truth"
      (for-each (lambda (scenario)
                  (let ((old (sr-prepare #t scenario)) (new (sr-prepare #f scenario)))
                    (check-equal? (sr-consume old scenario #t) (sr-expected old scenario))
                    (check-equal? (sr-consume new scenario #f) (sr-expected new scenario))))
                '(wide retained mixed cold small dense index native)))
    (test-case "committed timeout cuts and newly nonempty custom source slots match"
      (for-each
       (lambda (scenario)
         (let* ((program (sr-program scenario))
                (old (old-gerbil-ascent-make-engine program #t))
                (new (gerbil-ascent-make-engine program #t))
                (first ((.ref new '.run-timeout) 0)) (saved (sr-project first)))
           (check-equal? saved (sr-project ((.ref old '.run-timeout) 0)))
           (for-each (lambda (_) (check-equal? (sr-project ((.ref new '.run-timeout) 0))
                                              (sr-project ((.ref old '.run-timeout) 0)))) (iota 4))
           (check-equal? (sr-project (run new)) (sr-project (run old)))
           (for-each (lambda (engine) ((.ref engine '.append-source!) 'unused383 '(0 99))) (list new old))
           (check-equal? (sr-project (run new)) (sr-project (run old)))
           (check-equal? (sr-project first) saved)
           (check-equal? (eq? (run new) (run new)) #t))) '(wide mixed)))
    (test-case "aggregate readiness retains multiple pending and failed owners without history"
      (let* ((ready (make-storage-readiness)) (other (make-storage-readiness)) (reject? #f)
             (provider (sr-provider (lambda (_a _p _r) (when reject? (error "mutated storage failure")))
                                    (lambda (_) [])))
             (extend (gerbil-ascent-storage-engine-extension provider 2))
             (a (gerbil-ascent-storage-engine-state provider ready))
             (b (gerbil-ascent-storage-engine-state provider ready)))
        (extend a [] [] '(0 1) 10)
        (check-exception (gerbil-ascent-storage-check-readiness! ready) true)
        (gerbil-ascent-storage-admit-state! a)
        (gerbil-ascent-storage-check-readiness! ready)
        (extend a [] [] '(0 1) 10)
        (extend b [] [] '(0 2) 10)
        (gerbil-ascent-storage-admit-state! a)
        (check-exception (gerbil-ascent-storage-check-readiness! ready) true)
        (extend a [] [] '(0 3) 10)
        (gerbil-ascent-storage-admit-readiness! ready)
        (gerbil-ascent-storage-check-readiness! ready)
        (gerbil-ascent-storage-check-state! a)
        (gerbil-ascent-storage-check-state! b)
        (set! reject? #t)
        (check-exception (extend b [] [] '(0 4) 10) true)
        (check-exception (gerbil-ascent-storage-check-state! b) true)
        (check-exception (gerbil-ascent-storage-check-readiness! ready) true)
        (gerbil-ascent-storage-admit-state! a)
        (check-exception (gerbil-ascent-storage-check-readiness! ready) true)
        (gerbil-ascent-storage-check-readiness! other)))
    (test-case "custom callbacks retain aliases, private spines and duplicate call order"
      (def (observe maker)
        (let ((trace []) (v (gerbil-ascent-variable 'v)) (next (gerbil-ascent-variable 'next)))
          (let* ((provider
                  (.o (:: @ gerbil-ascent-set-storage-provider)
                      (.extend-rows
                       (lambda (_state all pending row _budget)
                         (let (admitted (map values row))
                           (set! trace (cons (list (eq? all pending) (map (cut map values <>) all)
                                                  (map (cut map values <>) pending) admitted) trace))
                           (when (pair? all) (set-car! (car all) 'poison))
                           (when (pair? pending) (set-car! (car pending) 'poison))
                           (set-car! row 'poison)
                           (list admitted (map values admitted)))))))
                 (atom (gerbil-ascent-atom 'counter (list (gerbil-ascent-literal 0) next)))
                 (program (gerbil-ascent-program
                           (list (gerbil-ascent-relation 'counter 2 '((0 0)) gerbil-ascent-hash-index-provider provider)
                                 (gerbil-ascent-relation 'unused 2 []))
                           (list (gerbil-ascent-rule (list atom atom)
                                   (list (gerbil-ascent-atom 'counter (list (gerbil-ascent-literal 0) v))
                                         (gerbil-ascent-guard '(v) (lambda (x) (< x 16)))
                                         (gerbil-ascent-binding 'next '(v) (lambda (x) (+ x 1)))))) 40 100 100))
                 (engine (maker program #t)) (first (run engine)) (saved (sr-project first)))
            ((.ref engine '.append-source!) 'unused '(0 42))
            (run engine)
            (check-equal? (sr-project first) saved)
            (list saved (reverse trace)))))
      (check-equal? (observe gerbil-ascent-make-engine) (observe old-gerbil-ascent-make-engine)))
    (test-case "custom index callback versions preserve complete traversal"
      (def (observe maker)
        (let ((trace []) (v (gerbil-ascent-variable 'v)))
          (let* ((provider
                  (.o (:: @ gerbil-ascent-hash-index-provider)
                      (.build-index (lambda (rows columns)
                                      (set! trace (cons (list 'build rows columns) trace))
                                      ((.ref gerbil-ascent-hash-index-provider '.build-index) rows columns)))
                      (.extend-index! (lambda (index rows columns)
                                        (set! trace (cons (list 'extend rows columns) trace))
                                        ((.ref gerbil-ascent-hash-index-provider '.extend-index!) index rows columns)))
                      (.lookup-index (lambda (index key)
                                       (set! trace (cons (list 'lookup key) trace))
                                       ((.ref gerbil-ascent-hash-index-provider '.lookup-index) index key)))))
                 (base (sr-program 'index))
                 (relations (.ref base 'relations))
                 (program (gerbil-ascent-program
                            (cons (.o (:: @ (car relations)) index-provider: provider) (cdr relations))
                            (.ref base 'rules) 200000 200000 200000))
                 (engine (maker program #t)) (first (run engine)))
            ((.ref engine '.append-source!) 'counter '(0 20))
            (list (sr-project first) (sr-project (run engine)) (reverse trace)))))
      (check-equal? (observe gerbil-ascent-make-engine) (observe old-gerbil-ascent-make-engine)))))
