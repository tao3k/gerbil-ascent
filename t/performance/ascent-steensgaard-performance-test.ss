;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .ref)
        :gerbil-ascent/applications/steensgaard
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!))
(import (only-in :gerbil-ascent/t/qualification/ascent-steensgaard-test steensgaard-truth)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-steensgaard-performance-test)

;; Independent partition saturation. It does not use Scheme clauses, UF,
;; the production equality Provider, or the explicit Datalog closure rules.
(def (check-vpt result expected)
  (let (actual ((.ref result 'rows-of) 'vpt))
    (check-equal? (.ref result 'finished) #t)
    (let (visited [])
      ((.ref result 'visit-rows) 'vpt [] [] (lambda (row) (set! visited (cons row visited))))
      (check-equal? (length visited) (length expected))
      (for-each (lambda (row) (check-equal? (and (member row visited) #t) #t)) expected))
    (for-each (lambda (row)
      (let ((visited []) (node (car row)))
        ((.ref result 'visit-rows) 'vpt '(0) (list node)
          (lambda (found) (set! visited (cons found visited))))
        (check-equal? (length visited) (length (filter (lambda (found) (equal? (car found) node)) expected)))
        (for-each (lambda (found) (check-equal? (and (member found expected) #t) #t)) visited))) expected)
    (check-exception ((.ref result 'visit-rows) 'vpt '(2) '(0) void) true)
    (check-exception ((.ref result 'visit-rows) 'vpt '(0) [] void) true)
    ((.ref result 'visit-rows) 'vpt [] [] (lambda (row) (set-car! row 'callback-mutation)))
    (check-equal? ((.ref result 'rows-of) 'vpt) actual)
    (check-equal? (length actual) (length expected))
    (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected)))
(def ascent-steensgaard-performance-test
  (test-suite "Native Steensgaard application measurements"
    (poo-flow-test-case "matched application solve and complete export include load store saturation"
      (unless (getenv "ASCENT_TEST_LIBRARY" #f)
        (error "matched performance samples require compiled native qualification"))
      (assert-native-library!)
      (let* ((n 16)
             (alloc (map (lambda (i) (list (+ n i) i)) (iota n)))
             (assign (map (lambda (i) (list i (+ i 1))) (iota (- n 1))))
             (load (map (lambda (i) (list (+ (* 2 n) i) i i)) (iota n)))
             (store (map (lambda (i) (list i i (+ (* 3 n) i))) (iota n)))
             (expected (steensgaard-truth alloc assign load store))
             (old (gerbil-ascent-steensgaard-program alloc assign load store #t))
             (new (gerbil-ascent-steensgaard-program alloc assign load store)))
        (check-vpt (gerbil-ascent-evaluate-program old) expected)
        (check-vpt (gerbil-ascent-evaluate-program new) expected)
        (def (sample program workers)
          (##gc)
          (let* ((counter (make-f64vector 2 0.)) (before (##process-statistics))
                 (start (current-jiffy)))
            (##get-bytes-allocated! counter 0)
            (let* ((result (gerbil-ascent-evaluate-program program workers: workers))
                   (rows ((.ref result 'rows-of) 'vpt))
                   (elapsed (- (current-jiffy) start)) (after (##process-statistics)))
              (##get-bytes-allocated! counter 1)
              (check-vpt result expected)
              (vector (* 1000000 (- (+ (f64vector-ref after 0) (f64vector-ref after 1))
                                    (+ (f64vector-ref before 0) (f64vector-ref before 1))))
                      (* 1000000 (/ elapsed (jiffies-per-second)))
                      ;; The VM allocation counter is thread-local. A caller
                      ;; subtraction cannot measure allocations of actor threads.
                      (and (= workers 1) (- (f64vector-ref counter 1) (f64vector-ref counter 0)))
                      (length rows)))))
        (for-each (lambda (pair)
          (let* ((old-first? (even? pair))
                 (a (sample (if old-first? old new) 1))
                 (b (sample (if old-first? new old) 1)))
            (displayln "STEENSGAARD-COST pair=" pair " old=" (if old-first? a b)
                       " new=" (if old-first? b a)) (force-output))) (iota 12))
        ;; Same explicit program at both capacities. Canonical equivalence views
        ;; also admit frozen worker reads; the coordinator owns every merge.
        (for-each (lambda (pair)
          (let* ((serial-first? (even? pair))
                 (a (sample old (if serial-first? 1 2)))
                 (b (sample old (if serial-first? 2 1))))
            (displayln "STEENSGAARD-WORKERS pair=" pair " serial=" (if serial-first? a b)
                       " parallel=" (if serial-first? b a)) (force-output))) (iota 6))))))
