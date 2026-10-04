;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :gerbil-ascent/program/graph gerbil-ascent-graph-components)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-graph-performance-test)

;;; Include the frozen implementation in this compilation unit so both paths
;;; are native without extending the build entrypoint with test-specific rules.
(include "../qualification/ascent-graph-fixture.ss")

;;; Only the SCC traversal is timed. Graph construction and GC are outside
;;; each paired sample; both paths are natively compiled.
(def (sample call expected)
  (let ((start (current-jiffy)) (last #f))
    (let loop ((n 8))
      (unless (zero? n)
        (set! last (call))
        (loop (- n 1))))
    (let (elapsed (- (current-jiffy) start))
      (check-equal? last expected)
      elapsed)))

(def (compare label graph target?)
  (let* ((expected (ascent-reference-graph-components graph))
         (old-call (lambda () (ascent-reference-graph-components graph)))
         (new-call (lambda () (gerbil-ascent-graph-components graph)))
         (old []) (new []) (wins 0))
    (sample old-call expected)
    (sample new-call expected)
    (let loop ((n 0))
      (when (< n 1000)
        (when (zero? (modulo n 20)) (##gc))
        (let-values (((a b)
                      (if (even? n)
                        (let* ((a (sample old-call expected))
                               (b (sample new-call expected))) (values a b))
                        (let* ((b (sample new-call expected))
                               (a (sample old-call expected))) (values a b)))))
          (set! old (cons a old))
          (set! new (cons b new))
          (when (< b a) (set! wins (+ wins 1))))
        (loop (+ n 1))))
    (let ((a (list-ref (list-sort < old) 500))
          (b (list-ref (list-sort < new) 500)))
      (displayln "GRAPH " label " pairs=1000 batch=8 wins=" wins
                 " reference-median-jiffies=" a " candidate-median-jiffies=" b)
      (force-output)
      (and (<= b a) (or (not target?) (>= wins 900))))))

(def ascent-graph-performance-test
  (test-suite "Explicit SCC traversal"
    (test-case "deep and branching targets qualify with a small control"
      (assert-native-library!)
      (let* ((count 1024)
             (vertices (iota count))
             (chain (list->vector
                     (map (lambda (n)
                            (if (= (+ n 1) count) [] (list (+ n 1)))) vertices)))
             (cycle (list->vector
                     (map (lambda (n) (list (modulo (+ n 1) count))) vertices)))
             (branching (list->vector
                         (map (lambda (n)
                                (filter (cut < <> count)
                                        (list (+ (* 2 n) 1) (+ (* 2 n) 2))))
                              vertices)))
             (qualified? #t))
        (for-each
         (lambda (entry)
           (unless (apply compare entry) (set! qualified? #f)))
         (list (list 'small '#((1) (0 2) ()) #f)
               (list 'chain chain #t)
               (list 'cycle cycle #t)
               (list 'branching branching #t)))
        (unless qualified? (error "explicit SCC traversal failed paired admission"))))))
