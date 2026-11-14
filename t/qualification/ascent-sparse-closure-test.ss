;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/candidate/closure
        :gerbil-ascent/t/performance/sparse-closure/fixture
        (prefix-in :gerbil-ascent/t/performance/sparse-closure/reference old-))
(export ascent-sparse-closure-test)
(def ascent-sparse-closure-test
  (test-suite "occupied-domain canonical closure"
    (test-case "complete consumer truth across sparse dense truncated empty and small domains"
      (for-each (lambda (scenario)
        (let ((old (sparse-prepare #t scenario)) (new (sparse-prepare #f scenario)))
          (sparse-verify! old scenario) (sparse-verify! new scenario)
          (check-equal? (sparse-consume new scenario) (sparse-consume old scenario))
          (displayln "CLOSURE-CHECKED " scenario) (force-output)))
        '(sparse truncated dense small empty)))
    (test-case "all tiny directed graphs preserve shortest nonempty supports and numeric order"
      (let (edges '((0 0) (0 1) (0 2) (1 0) (1 1) (1 2) (2 0) (2 1) (2 2)))
        (for-each (lambda (mask)
          (let (selected (filter-map (lambda (edge bit)
                          (and (not (zero? (bitwise-and mask (arithmetic-shift 1 bit))))
                               (cons edge (+ 100 (- 8 bit))))) edges (iota 9)))
            (for-each (lambda (radix)
              (let* ((facts (map (lambda (entry)
                                  (cons (+ (* (caar entry) radix) (cadar entry)) (cdr entry))) selected))
                     (old (sparse-project (old-gerbil-ascent-closure-candidates facts radix 16 16 16)))
                     (new (sparse-project (gerbil-ascent-closure-candidates facts radix 16 16 16))))
                (check-equal? new old))) '(3 17))
            (when (zero? (modulo mask 32))
              (displayln "CLOSURE-GRAPH-CHECKED " mask "/512") (force-output)))) (iota 512))))
    (test-case "exact large IDs duplicates input caps and theoretical pair caps retain admission"
      (let* ((radix (expt 2 64))
             (facts (list (cons (+ (* (- radix 2) radix) (- radix 1)) 7))))
        (check-equal? (sparse-project (gerbil-ascent-closure-candidates facts radix 1 4 4))
                      (list 'complete 1 (list (list (caar facts) 1 '(7) 'base)))))
      (for-each (lambda (call)
        (check-exception (call '((1 . 7) (1 . 7)) 8 16 64 64) true)
        (check-exception (call '((1 . 7) (2 . 8)) 8 1 64 64) true)
        (check-exception (call '((1 . 7) (2 . 8)) 8 16 8 64) true)
        (check-exception (call '((64 . 7)) 8 16 64 64) true))
        (list gerbil-ascent-closure-candidates old-gerbil-ascent-closure-candidates)))))
