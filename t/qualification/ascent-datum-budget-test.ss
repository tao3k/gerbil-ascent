;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
 (only-in :gerbil-ascent/candidate/datum reasoning-bounded-data?)
 (only-in "reference/datum-budget.ss" reference-bounded-data?))
(export ascent-datum-budget-test)
(def ascent-datum-budget-test
 (test-suite "Bounded counter specialization preserves exact fallback semantics"
  (test-case "finite tree and budget grids match the independent original walk"
   (for-each (lambda (datum)
    (for-each (lambda (nodes)
     (for-each (lambda (depth)
      (check-equal? (reasoning-bounded-data? datum nodes depth)
                    (reference-bounded-data? datum nodes depth)))
      '(-1 0 1 2 4 16 1048576 1048577)))
     '(-1 0 1 2 4 16 1048576 1048577)))
    (list '() #f 17 'a #\a '(a b) '((a . b) (c d)) '(a . b) "rejected" (vector 1))))
  (test-case "cycles and shared acyclic branches preserve rejection and acceptance"
   (let* ((cycle (list 'a)) (shared (list 'b 'c)) (tree (list shared shared)))
    (set-cdr! cycle cycle)
    (for-each (lambda (datum)
     (check-equal? (reasoning-bounded-data? datum 4096 128)
                   (reference-bounded-data? datum 4096 128))) (list cycle tree))))
  (test-case "huge and nonfixnum budgets retain generic arithmetic behavior"
   (for-each (lambda (cap)
    (for-each (lambda (datum)
     (check-equal? (reasoning-bounded-data? datum cap cap)
                   (reference-bounded-data? datum cap cap)))
     (list 'a '(a (b) c) '())))
    (list (arithmetic-shift 1 80) 1.5 +inf.0 -inf.0)))))
