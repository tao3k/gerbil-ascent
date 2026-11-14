;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :gerbil-ascent/candidate/grounding-plan
        (only-in :gerbil-ascent/candidate/funs candidate-bind-atom)
        :gerbil-ascent/t/performance/grounding-plan/fixture)
(export ascent-grounding-plan-test)
(def ascent-grounding-plan-test
  (test-suite "invocation-owned grounding expressions"
    (test-case "all two-field matches preserve repeated variables literals and prior bindings"
      (for-each (lambda (a)
        (for-each (lambda (b)
          (let* ((atom (list 'r a b)) (match-row (prepare-grounding-atom atom)))
            (for-each (lambda (x)
              (for-each (lambda (y)
                (for-each (lambda (prior)
                  (let ((before (map (lambda (p) (cons (car p) (cdr p))) prior))
                        (row (list x y)))
                    (check-equal? (match-row row prior) (candidate-bind-atom atom row prior))
                    (check-equal? prior before)))
                  '(() ((?x . #f)) ((?y . 0)) ((?x . 1) (?x . 0) (?y . #f)))))
                '(#f 0 1 literal))) '(#f 0 1 literal))))
          '(?_ ?x ?y #f 0 1 literal ?))) '(?_ ?x ?y #f 0 1 literal ?)))
    (test-case "empty atom preserves binding identity and failed match admits no later binding"
      (let (prior '((?x . #f)))
        (check-eq? ((prepare-grounding-atom '(zero)) [] prior) prior)
        (check-equal? ((prepare-grounding-atom '(r 7 ?new)) '(8 1) prior) #f)
        (check-equal? prior '((?x . #f)))))
    (test-case "prepared head and scalar body preserve false values filters and computations"
      (let (plan (prepare-grounding-rule
                  (vector '(p ?y ?x 7) '((s ?x) (where (even? ?x)) (compute ?y (+ ?x ?x))) 42)))
        (check-equal? (grounding-rule-name plan) 'p)
        (check-equal? (grounding-rule-label plan) 42)
        (with ([read filter compute] (grounding-rule-body plan))
          (let* ((bindings ((grounding-clause-apply read) '(2) []))
                 (filtered ((grounding-clause-apply filter) bindings))
                 (computed ((grounding-clause-apply compute) filtered)))
            (check-equal? ((grounding-rule-head plan) computed) '(4 2 7)))
          (check-equal? ((grounding-clause-apply filter) '((?x . #f))) #f)
          (check-equal? ((grounding-clause-apply compute) '((?x . 2) (?y . #f))) #f))))
    (test-case "complete frozen proof replay graph opening and independent truth agree"
      (for-each (lambda (scenario)
        (let ((old (grounding-prepare #t scenario)) (new (grounding-prepare #f scenario)))
          (grounding-verify! old scenario) (grounding-verify! new scenario)
          (check-equal? (grounding-consume new scenario) (grounding-consume old scenario))))
        '(proof graph small scalar)))
    (test-case "every small proof and graph work boundary preserves frozen status nodes and roots"
      (for-each (lambda (scenario)
        (let ((old (grounding-prepare #t scenario)) (new (grounding-prepare #f scenario)))
          (for-each (lambda (budget)
            (check-equal? (grounding-consume new scenario budget) (grounding-consume old scenario budget)))
            (iota 80 1))
          (when (eq? scenario 'graph-small)
            (for-each (lambda (limit)
              (check-equal? (grounding-consume new scenario 100000 limit)
                            (grounding-consume old scenario 100000 limit))) (iota 8 1)))))
        '(small scalar graph-small)))))
