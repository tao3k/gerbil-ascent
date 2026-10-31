;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/scheme-language
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        :gerbil-ascent/core/positive-plan
        (only-in :gerbil-ascent/t/qualification/fixtures/semi-naive/oracle
                 finite-domain-closure))
(export ascent-rule-cost-test)

;;; The language and evaluator are unchanged. The reuse lane names the complete
;;; common prefix as an ordinary relation, retaining all witness variables.
(def (declaration edges suffix factored?)
  (if factored?
    (relational-program
      (relation edge (a b) edges) (relation tail (a b) suffix)
      (relation prefix (a b c d)) (relation left (a b)) (relation right (a b))
      (rule (prefix ?x ?y ?z ?t) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t))
      (rule (left ?x ?w) (prefix ?x ?y ?z ?t) (tail ?t ?w))
      (rule (right ?x ?w) (prefix ?x ?y ?z ?t) (tail ?t ?w))
      (limits 1000 10000 12000))
    (relational-program
      (relation edge (a b) edges) (relation tail (a b) suffix)
      (relation prefix (a b c d)) (relation left (a b)) (relation right (a b))
      (rule (left ?x ?w) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t) (tail ?t ?w))
      (rule (right ?x ?w) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t) (tail ?t ?w))
      (limits 1000 10000 12000))))
(def direct-rules
  '(((left x w) (edge x y) (edge y z) (edge z t) (tail t w))
    ((right x w) (edge x y) (edge y z) (edge z t) (tail t w))))
(def factored-rules
  '(((prefix x y z t) (edge x y) (edge y z) (edge z t))
    ((left x w) (prefix x y z t) (tail t w))
    ((right x w) (prefix x y z t) (tail t w))))
(def (count-of receipt name) (cdr (assq name receipt)))
(def (run edges domain factored?)
  (let* ((suffix (map (lambda (x) (list x x)) domain))
         (program (declaration edges suffix factored?))
         (cost (make-positive-plan-cost))
         (actual (call-with-positive-plan-cost cost
                   (lambda () (gerbil-ascent-evaluate-program program))))
         (expected (finite-domain-closure domain
                     (list (cons 'edge edges) (cons 'tail suffix)
                           (cons 'prefix []) (cons 'left []) (cons 'right []))
                     (if factored? factored-rules direct-rules))))
    (check-equal? (.ref actual 'finished) #t)
    (for-each (lambda (name)
                (let ((rows ((.ref actual 'rows-of) name))
                      (want (cdr (assq name expected))))
                  (check-equal? (length rows) (length want))
                  (check-equal? (andmap (lambda (row) (and (member row want) #t)) rows) #t)))
              '(edge tail prefix left right))
    ;; Measurement must preserve the original evaluator's complete answers.
    (let (plain (gerbil-ascent-evaluate-program program))
      (for-each (lambda (name)
                  (check-equal? ((.ref actual 'rows-of) name)
                                ((.ref plain 'rows-of) name))) '(edge tail prefix left right)))
    (positive-plan-cost-snapshot cost)))
(def (two-node-graph mask)
  (filter-map (lambda (i)
                (and (not (zero? (bitwise-and mask (arithmetic-shift 1 i))))
                     (list (quotient i 2) (modulo i 2)))) (iota 4)))
(def ascent-rule-cost-test
  (test-suite "Native DSL plan costs and explicit prefix reuse"
    (test-case "collector ownership excludes unrelated solves and parallel routes"
      (let ((program (declaration '((0 1)) '((0 0) (1 1)) #f))
            (cost (make-positive-plan-cost)))
        (call-with-positive-plan-cost cost
          (lambda () (gerbil-ascent-evaluate-program program)))
        (check-exception
          (call-with-positive-plan-cost cost
            (lambda () (gerbil-ascent-evaluate-program program))) error?)
        (check-exception
          (call-with-positive-plan-cost (make-positive-plan-cost)
            (lambda () (gerbil-ascent-evaluate-program program workers: 2))) error?)))
    (test-case "all two-node graphs agree with independent finite grounding"
      (for-each (lambda (mask)
                  (for-each (lambda (factored?) (run (two-node-graph mask) '(0 1) factored?))
                            '(#f #t))) (iota 16)))
    (test-case "retain sparse sharing and dense materialization tradeoffs"
      (let* ((chain '((0 1) (1 2) (2 3)))
             (before (run chain '(0 1 2 3) #f))
             (after (run chain '(0 1 2 3) #t)))
        (displayln "RULE-COST chain baseline=" before " factored=" after)
        (check-equal? (< (count-of after 'candidate-rows)
                         (count-of before 'candidate-rows)) #t)
        (check-equal? (> (count-of before 'repeated-prefixes) 0) #t))
      (let* ((dense (two-node-graph 15))
             (before (run dense '(0 1) #f)) (after (run dense '(0 1) #t)))
        (displayln "RULE-COST dense baseline=" before " factored=" after)
        ;; The first run falsified a candidate-scan non-improvement hypothesis;
        ;; retain that log. This unchanged graph has 2^4 prefix witnesses,
        ;; independently checked above, plus four rows in each exported answer.
        ;; Materialization overhead is real even when matching gets cheaper.
        (check-equal? (count-of before 'admitted-rows) 8)
        (check-equal? (count-of after 'admitted-rows) 24)))
    (test-case "unfinished traversal retains partial counters and cannot emit"
      (let* ((atom (vector 0 '((variable . x)) [] [] []))
             (head (vector 1 '((variable . x))))
             (plan (gerbil-ascent-compile-positive-plan [head] [(vector 'atom atom)]))
             (cost (make-positive-plan-cost)) (emitted 0))
        (check-exception
          (call-with-positive-plan-cost cost
            (lambda ()
              (gerbil-ascent-run-positive-plan! plan (vector #f) -1
                (lambda args '((0) (1)))
                (lambda args (set! emitted (+ emitted 1)))
                (lambda () (error "frozen diagnostic interruption"))))) error?)
        (check-equal? emitted 0)
        (check-equal? (count-of (positive-plan-cost-snapshot cost) 'candidate-rows) 1)
        (check-equal? (count-of (positive-plan-cost-snapshot cost) 'complete-witnesses) 0)))))
