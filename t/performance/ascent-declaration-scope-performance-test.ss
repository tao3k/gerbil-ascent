;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-schema
                 gerbil-ascent-program-analysis)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-declaration-scope-performance-test)
(include "../qualification/ascent-declaration-scope-fixture.ss")

;;; Run this same compiled module on 822348c and the candidate, reversing
;;; process order for a repeat. No source helper or fixture is timed.
(def (sample call)
  (let* ((start (current-jiffy)) (value (call))
         (elapsed (- (current-jiffy) start)))
    (values elapsed value)))

(def (measure kind width heads)
  (let-values (((template expected names) (ascent-scope-fixture kind width heads)))
    (let* ((relations (.ref template 'relations))
           (rules (.ref template 'rules))
           (schema (gerbil-ascent-program-schema template relations))
           (compile-times []) (cold-times []) (last-engine #f))
      (def (check-run engine)
        (let (result (engine))
          (for-each
           (lambda (name) (check-equal? ((.ref result 'rows-of) name) (list expected)))
           names)))
      (check-run (gerbil-ascent-make-engine template #f))
      (let loop ((n 0))
        (when (< n 1000)
          (when (zero? (modulo n 20)) (##gc))
          ;; A fresh POO snapshot inherits the already validated declarations
          ;; and limits unchanged. Neither constructor validation nor copying
          ;; is timed; distinct identity excludes schema and analysis caches.
          (let (program (.o (:: @ template)))
            (check-equal? (eq? program template) #f)
            (let-values (((compile-time analysis)
                          (sample (lambda ()
                                    (gerbil-ascent-prepare-program relations rules schema #f))))
                         ((cold-time engine)
                          (sample (lambda () (gerbil-ascent-make-engine program #f)))))
              (check-equal? (length (vector-ref analysis 2)) 1)
              (let (cached
                    (gerbil-ascent-program-analysis program relations rules
                      (lambda () (error "cold engine did not compile its declarations"))))
                (check-equal? (eq? (vector-ref cached 0) relations) #t)
                (check-equal? (eq? (vector-ref cached 1) rules) #t)
                (for-each (lambda (slot)
                            (check-equal? (vector-ref analysis slot)
                                          (vector-ref cached slot))) '(2 3 4)))
              (set! last-engine engine)
              (set! compile-times (cons compile-time compile-times))
              (set! cold-times (cons cold-time cold-times))
              (displayln "SCOPE-SAMPLE " kind " width=" width " heads=" heads
                         " n=" n " compile=" compile-time " cold=" cold-time)))
          (when (zero? (modulo (+ n 1) 100))
            (displayln "SCOPE-PROGRESS " kind " width=" width " " (+ n 1) "/1000")
            (force-output))
          (loop (+ n 1))))
      (check-run last-engine)
      (displayln "SCOPE-RESULT " kind " width=" width " heads=" heads
                 " samples=1000 compile-median-jiffies="
                 (list-ref (list-sort < compile-times) 500)
                 " cold-median-jiffies=" (list-ref (list-sort < cold-times) 500))
      (force-output))))

(def ascent-declaration-scope-performance-test
  (test-suite "Declaration scope compilation and cold engine construction"
    (test-case "1000 cold samples retain declaration parity and endpoint solve results"
      (assert-native-library!)
      (for-each (lambda (shape) (apply measure shape))
                '((atom 1 1) (atom 8 1) (atom 128 8) (atom 512 8)
                  (generator 128 2) (aggregate 128 2)
                  (pattern 128 2) (expression 512 2))))))
