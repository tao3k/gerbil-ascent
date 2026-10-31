;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/scheme-language
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        :gerbil-ascent/core/positive-plan
        (only-in :gerbil-ascent/program/analysis
                 gerbil-ascent-program-analysis gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/t/qualification/fixtures/semi-naive/oracle
                 finite-domain-closure))
(export ascent-rule-cost-test)

;;; Both lanes use the existing language and the same native evaluator. The
;;; reuse lane names the complete
;;; common prefix as an ordinary relation, retaining all witness variables.
(def (declaration edges suffix factored?)
  (cond
   ((eq? factored? 'projected)
    (relational-program
      (relation edge (a b) edges) (relation tail (a b) suffix)
      (relation prefix (a b)) (relation left (a b)) (relation right (a b))
      (rule (prefix ?x ?t) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t))
      (rule (left ?x ?w) (prefix ?x ?t) (tail ?t ?w))
      (rule (right ?x ?w) (prefix ?x ?t) (tail ?t ?w))
      (limits 1000 10000 12000)))
   (factored?
    (relational-program
      (relation edge (a b) edges) (relation tail (a b) suffix)
      (relation prefix (a b c d)) (relation left (a b)) (relation right (a b))
      (rule (prefix ?x ?y ?z ?t) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t))
      (rule (left ?x ?w) (prefix ?x ?y ?z ?t) (tail ?t ?w))
      (rule (right ?x ?w) (prefix ?x ?y ?z ?t) (tail ?t ?w))
      (limits 1000 10000 12000)))
   (else
    (relational-program
      (relation edge (a b) edges) (relation tail (a b) suffix)
      (relation prefix (a b c d)) (relation left (a b)) (relation right (a b))
      (rule (left ?x ?w) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t) (tail ?t ?w))
      (rule (right ?x ?w) (edge ?x ?y) (edge ?y ?z) (edge ?z ?t) (tail ?t ?w))
      (limits 1000 10000 12000)))))
(def direct-rules
  '(((left x w) (edge x y) (edge y z) (edge z t) (tail t w))
    ((right x w) (edge x y) (edge y z) (edge z t) (tail t w))))
(def factored-rules
  '(((prefix x y z t) (edge x y) (edge y z) (edge z t))
    ((left x w) (prefix x y z t) (tail t w))
    ((right x w) (prefix x y z t) (tail t w))))
(def projected-rules
  '(((prefix x t) (edge x y) (edge y z) (edge z t))
    ((left x w) (prefix x t) (tail t w))
    ((right x w) (prefix x t) (tail t w))))
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
                     (cond ((eq? factored? 'projected) projected-rules)
                           (factored? factored-rules) (else direct-rules)))))
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
    ;; Each repeat is assigned exactly once. Neither bucket implies waste.
    (let (receipt (positive-plan-cost-snapshot cost))
      (check-equal? (count-of receipt 'repeated-prefixes)
                    (+ (count-of receipt 'same-plan-prefix-revisits)
                       (count-of receipt 'cross-plan-prefix-revisits)))
      (check-equal? (count-of receipt 'repeated-candidate-visits)
                    (+ (count-of receipt 'same-plan-candidate-revisits)
                       (count-of receipt 'cross-plan-candidate-revisits))))
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
        ;; One full initial traversal costs 3+9+6+4 candidates per rule.
        ;; Later empty delta pivots must not rebuild either bound prefix.
        (check-equal? (count-of before 'candidate-rows) 44)
        (check-equal? (count-of before 'partial-matches) 14)
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
    (test-case "existential prefix projection preserves exports on every two-node graph"
      (for-each
       (lambda (mask)
         (let* ((edges (two-node-graph mask)) (suffix '((0 0) (1 1)))
                (direct (gerbil-ascent-evaluate-program (declaration edges suffix #f)))
                (projected (gerbil-ascent-evaluate-program (declaration edges suffix 'projected))))
           (run edges '(0 1) 'projected)
           (for-each
            (lambda (name)
              (let ((before ((.ref direct 'rows-of) name))
                    (after ((.ref projected 'rows-of) name)))
                (check-equal? (length after) (length before))
                (check-equal? (andmap (lambda (row) (and (member row before) #t)) after) #t)))
            '(left right)))) (iota 16))
      (for-each
       (lambda (input)
         (let* ((edges (car input)) (domain (cadr input))
                (retained (run edges domain #t))
                (projected (run edges domain 'projected)))
           (displayln "RULE-COST projected input=" edges " receipt=" projected)
           (check-equal? (<= (count-of projected 'admitted-rows)
                             (count-of retained 'admitted-rows)) #t)
           (check-equal? (<= (count-of projected 'complete-witnesses)
                             (count-of retained 'complete-witnesses)) #t)
           (when (= (length domain) 2)
             (check-equal? (count-of projected 'candidate-rows) 76)
             (check-equal? (count-of projected 'complete-witnesses) 24)
             (check-equal? (count-of projected 'admitted-rows) 12))))
       (list (list '((0 1) (1 2) (2 3)) '(0 1 2 3))
             (list (two-node-graph 15) '(0 1)))))
    (test-case "projected prefix survives one support withdrawal but not the last"
      (let* ((edges '((0 1) (1 1) (1 3) (0 2) (2 2) (2 3)))
             (suffix '((0 0) (1 1) (2 2) (3 3)))
             (session (relational-open-program-session (declaration edges suffix 'projected)))
             (old (relational-program-session-run session)))
        (check-equal? (and (member '(0 3) (relational-program-query old 'left)) #t) #t)
        (for-each
         (lambda (remaining)
           (relational-program-replace-source! session 'edge remaining)
           (let* ((actual (relational-program-session-run session))
                  (expected (finite-domain-closure '(0 1 2 3)
                              (list (cons 'edge remaining) (cons 'tail suffix)
                                    (cons 'prefix []) (cons 'left []) (cons 'right []))
                              projected-rules)))
             (for-each
              (lambda (name)
                (let ((rows (relational-program-query actual name)) (want (cdr (assq name expected))))
                  (check-equal? (length rows) (length want))
                  (check-equal? (andmap (lambda (row) (and (member row want) #t)) rows) #t)))
              '(left right))
             (check-equal? (and (member '(0 3) (relational-program-query actual 'left)) #t)
                           (and (member '(0 2) remaining) #t))))
         '(((1 1) (1 3) (0 2) (2 2) (2 3))
           ((1 1) (1 3) (2 2) (2 3))))
        (check-equal? (and (member '(0 3) (relational-program-query old 'left)) #t) #t)))
    (test-case "scalar empty-pivot pruning never mutates cached rule analysis"
      (let* ((program (declaration '((0 1) (1 2) (2 3)) '((0 0) (1 1) (2 2) (3 3)) #f))
             (relations (.ref program 'relations)) (rules (.ref program 'rules))
             (schema (gerbil-ascent-program-schema program relations))
             (analysis (gerbil-ascent-program-analysis program relations rules
                         (lambda () (gerbil-ascent-prepare-program relations rules schema #f)))))
        (def (snapshot)
          (map (lambda (plans)
                 (map (lambda (rule) (vector->list (vector-ref rule 4))) plans))
               (vector->list (vector-ref analysis 5))))
        (let (before (snapshot))
          (gerbil-ascent-evaluate-program program)
          (check-equal? (snapshot) before)
          (gerbil-ascent-evaluate-program program)
          (check-equal? (snapshot) before))))
    (test-case "fresh pruning preserves retained source revision and sibling isolation"
      (let* ((edges '((0 1) (1 2) (2 3)))
             (program (declaration edges '((0 0) (1 1) (2 2) (3 3)) #f))
             (first (relational-open-program-session program))
             (sibling (relational-open-program-session program))
             (old (relational-program-session-run first)))
        ;; The fresh solve may share immutable planning, never a Session frame.
        (gerbil-ascent-evaluate-program program)
        (relational-program-replace-source! first 'edge '((0 1) (2 3)))
        (let ((withdrawn (relational-program-session-run first))
              (other (relational-program-session-run sibling)))
          (check-equal? (relational-program-query withdrawn 'left) [])
          (check-equal? (relational-program-query old 'left) '((0 3)))
          (check-equal? (relational-program-query other 'left) '((0 3))))
        (relational-program-replace-source! first 'edge edges)
        (check-equal? (relational-program-query (relational-program-session-run first) 'left)
                      '((0 3)))))
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
