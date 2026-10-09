;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/component-plan
 :gerbil-ascent/t/performance/component-construction/fixture
 (prefix-in :gerbil-ascent/t/performance/component-construction/reference old-))
(export ascent-component-construction-test)
(def (check-analysis analysis)
 (let ((a (old-gerbil-ascent-compile-positive-components analysis))
       (b (gerbil-ascent-compile-positive-components analysis)))
  (check-equal? (construction-shape b) (construction-old-shape a))
  (for-each (lambda (component)
   (for-each (lambda (rule)
    (let (plan (vector-ref rule 0))
     (for-each (lambda (original)
      (let (full (vector-ref original 5))
       (when (equal? (vector-ref plan 0) (vector-ref full 0))
        (check-equal? (eq? plan full) #t)))) (vector-ref (vector-ref analysis 5) 0))))
    (positive-component-rules component))) b)))
(def ascent-component-construction-test
 (test-suite "SCC construction ownership and order"
  (test-case "all three-node graphs with duplicate edges and projected duplicate heads"
   (for-each (lambda (bits)
    (let (graph (list->vector
      (map (lambda (source)
       (apply append (map (lambda (target)
        (if (bit-set? (+ (* source 3) target) bits) (list target target) [])) (iota 3)))) (iota 3))))
     (for-each (lambda (heads) (check-analysis (construction-analysis graph heads)))
      '(() (()) ((0)) ((0 1 0 2)) ((2 1) (0 0) (1 2 1)))))
    (when (zero? (modulo (+ bits 1) 16))
     (displayln "CONSTRUCTION-GRAPHS " (+ bits 1) "/512") (force-output))) (iota 512)))
  (test-case "predecessor promotion retains first encounter order and deduplicates old entries"
   (check-analysis (construction-analysis '#((4 4) (4) (4 4) (4) ()) '((4) (4 4)))))
  (test-case "bitmap promotion deduplicates a noncontiguous SCC and preserves independently derived order"
   (let* ((graph (list->vector (map (lambda (id)
            (cond ((= id 128) []) ((= id 0) '(96 128 128))
                  ((= id 96) '(0 128)) (else '(128 128)))) (iota 129))))
          (analysis (construction-analysis graph '((128) (0 96))))
          (components (gerbil-ascent-compile-positive-components analysis))
          (membership (make-vector 129 #f)) (expected []))
    (check-analysis analysis)
    (for-each (lambda (component)
     (for-each (lambda (id) (vector-set! membership id component))
               (positive-component-members component))) components)
    (for-each (lambda (source)
     (let (id (positive-component-id (vector-ref membership source)))
      (unless (memv id expected) (set! expected (cons id expected))))) (iota 128))
    (check-equal? (positive-component-predecessors (vector-ref membership 128)) expected)
    (check-equal? (length expected) 127)))
  (test-case "empty analysis has no published metadata"
   (check-analysis (construction-analysis '#() [])))))
