;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/scheme-language
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program gerbil-ascent-make-engine)
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
(def recursive-rules
  '(((path x y) (edge x y))
    ((path x z) (path x y) (path y z))
    ((answer x w) (edge x y) (path y z) (path z w))))
(def (recursive-declaration edges)
  (relational-program
    (relation edge (a b) edges) (relation path (a b)) (relation answer (a b))
    (rule (path ?x ?y) (edge ?x ?y))
    (rule (path ?x ?z) (path ?x ?y) (path ?y ?z))
    (rule (answer ?x ?w) (edge ?x ?y) (path ?y ?z) (path ?z ?w))
    (limits 1000 10000 12000)))
(def (check-recursive edges domain actual)
  (let (expected (finite-domain-closure domain
                  (list (cons 'edge edges) (cons 'path []) (cons 'answer [])) recursive-rules))
    (check-equal? (.ref actual 'finished) #t)
    (for-each
     (lambda (name)
       (let ((rows ((.ref actual 'rows-of) name)) (want (cdr (assq name expected))))
         (check-equal? (length rows) (length want))
         (check-equal? (andmap (lambda (row) (and (member row want) #t)) rows) #t)))
     '(edge path answer))))
(def (run-recursive edges domain (trace? #f) (empty-reuse? #f))
  (let* ((program (recursive-declaration edges)) (cost (make-positive-plan-cost #t trace?))
         (actual (call-with-positive-plan-cost cost
                   (lambda () (gerbil-ascent-evaluate-program program empty-bucket-reuse?: empty-reuse?))))
         (plain (gerbil-ascent-evaluate-program program empty-bucket-reuse?: empty-reuse?)))
    (check-recursive edges domain actual)
    (for-each (lambda (name)
                (check-equal? ((.ref actual 'rows-of) name) ((.ref plain 'rows-of) name)))
              '(edge path answer))
    (when empty-reuse?
      (let (baseline (gerbil-ascent-evaluate-program program))
        (for-each (lambda (name) (check-equal? ((.ref actual 'rows-of) name)
                                              ((.ref baseline 'rows-of) name))) '(edge path answer))))
    ;; Revisited prefixes may feed new suffixes in later rounds, but the same
    ;; complete supporting tuple must not be rescheduled by another pivot.
    (check-equal? (count-of (positive-plan-cost-snapshot cost) 'same-plan-complete-revisits) 0)
    (when trace?
      (let ((groups (make-hash-table)) (visits (positive-plan-cost-visits cost))
            (productive 0) (dead 0) (rejected 0))
        (def (complete? visit)
          (and (list-ref visit 3)
               (= (list-ref visit 2)
                  (- (length (cdr (list-ref recursive-rules (caddr (car visit))))) 1))))
        (def (has-extension? visit)
          (ormap (lambda (other)
                   (and (equal? (take visit 2) (take other 2)) (complete? other)
                        (equal? (list-ref visit 5)
                                (take (list-ref other 5) (length (list-ref visit 5)))))) visits))
        (for-each
         (lambda (visit)
           (when (eq? (list-ref visit 4) 'same-plan)
             (let (key (take visit 4))
               (hash-put! groups key (+ 1 (or (hash-get groups key) 0))))
             (if (not (list-ref visit 3)) (set! rejected (+ rejected 1))
               (if (has-extension? visit)
                 (set! productive (+ productive 1)) (set! dead (+ dead 1)))))) visits)
        (check-equal? (+ productive dead rejected)
                      (count-of (positive-plan-cost-snapshot cost) 'same-plan-candidate-revisits))
        (displayln "REVISIT-SUMMARY source=" edges " productive=" productive
                   " no-complete-extension=" dead " rejected=" rejected)
        (check-equal? rejected 0)
        (let (chain? (equal? edges '((0 1) (1 2) (2 3))))
          (check-equal? productive (if chain? 2 0))
          (check-equal? dead (if chain? 26 13))
          (when chain?
            ;; The same answer prefix has no completion in round 1 but does
            ;; in round 2. A cached prefix failure cannot survive suffix delta.
            (let (edge-prefix (filter (lambda (visit)
                                       (and (= (caddr (car visit)) 2)
                                            (= (list-ref visit 2) 0)
                                            (equal? (list-ref visit 5) '((0 1))))) visits))
              (check-equal? (ormap (lambda (visit) (and (= (cadr (car visit)) 1)
                                                       (not (has-extension? visit)))) edge-prefix) #t)
              (check-equal? (ormap (lambda (visit) (and (= (cadr (car visit)) 2)
                                                       (has-extension? visit))) edge-prefix) #t))))
        (hash-for-each (lambda (key count) (displayln "REVISIT location/pivot/depth/matched=" key " count=" count)) groups)))
    (positive-plan-cost-snapshot cost)))
(def ascent-rule-cost-test
  (test-suite "Native DSL plan costs and explicit prefix reuse"
    (test-case "empty bucket reuse is explicit and refuses unsupported engine routes"
      (let (program (recursive-declaration '((0 1))))
        (check-exception (gerbil-ascent-evaluate-program program empty-bucket-reuse?: 'force) error?)
        (check-exception (gerbil-ascent-evaluate-program program workers: 2 empty-bucket-reuse?: #t) error?)
        (check-exception (gerbil-ascent-evaluate-program program canceled?: (lambda () #f)
                                                        empty-bucket-reuse?: #t) error?)
        (check-exception (gerbil-ascent-make-engine program #t #f #f #f #f #f 1 #f #t) error?))
      (let (program (relational-program
                      (relation input (x) '((0))) (relation blocked (x)) (relation out (x))
                      (rule (out ?x) (input ?x) (not (blocked ?x))) (limits 16 32 64)))
        (check-equal? ((.ref (gerbil-ascent-evaluate-program program) 'rows-of) 'out) '((0)))
        (check-exception (gerbil-ascent-evaluate-program program empty-bucket-reuse?: #t) error?)))
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
    (test-case "recursive matching and equal-size source revisions agree with finite grounding"
      (for-each (lambda (mask)
                  (for-each (lambda (reuse?) (run-recursive (two-node-graph mask) '(0 1) #f reuse?)) '(#f #t))) (iota 16))
      (let* ((first '((0 1) (1 2) (2 3)))
             (changed '((0 1) (1 2) (3 2)))
             (session (relational-open-program-session (recursive-declaration first)))
             (old (relational-program-session-run session)))
        (check-equal? (relational-program-query old 'answer) '((0 3)))
        (for-each
         (lambda (edges)
           (for-each
            (lambda (reuse?)
             (let (cost (run-recursive edges '(0 1 2 3) #t reuse?))
             (displayln "RULE-COST empty-reuse=" reuse? " recursive edges=" edges " receipt=" cost)
             (check-equal? (count-of cost 'candidate-rows) (if (equal? edges first) 48 25))
             (check-equal? (count-of cost 'complete-witnesses) (if (equal? edges first) 8 4))
             (check-equal? (count-of cost 'admitted-rows) (if (equal? edges first) 7 4))
             (check-equal? (count-of cost 'physical-index-probes)
                           (if (equal? edges first) (if reuse? 31 37) (if reuse? 11 18)))
             (check-equal? (count-of cost 'empty-cell-hits)
                           (if reuse? (if (equal? edges first) 6 7) 0)))) '(#f #t))
           (relational-program-replace-source! session 'edge edges)
           ;; Retained measurement remains unsupported; check its answers here
           ;; and report costs only for the separately checked fresh solve.
           (let* ((result (relational-program-session-run session))
                  (expected (finite-domain-closure '(0 1 2 3)
                              (list (cons 'edge edges) (cons 'path []) (cons 'answer []))
                              recursive-rules)))
             (for-each
              (lambda (name)
                (let ((rows (relational-program-query result name)) (want (cdr (assq name expected))))
                  (check-equal? (length rows) (length want))
                  (check-equal? (andmap (lambda (row) (and (member row want) #t)) rows) #t)))
              '(path answer))))
         (list first changed first))
        (check-equal? (relational-program-query old 'answer) '((0 3)))))
    (test-case "retain sparse sharing and dense materialization tradeoffs"
      (let* ((chain '((0 1) (1 2) (2 3)))
             (before (run chain '(0 1 2 3) #f))
             (after (run chain '(0 1 2 3) #t)))
        (displayln "RULE-COST chain baseline=" before " factored=" after)
        ;; Exact bound-key selection visits 3+2+1+1 rows per rule; index
        ;; construction/extension and probes are charged separately.
        (check-equal? (count-of before 'candidate-rows) 14)
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
             (check-equal? (count-of projected 'candidate-rows) 44)
             (check-equal? (count-of projected 'complete-witnesses) 24)
             (check-equal? (count-of projected 'admitted-rows) 12))))
       (list (list '((0 1) (1 2) (2 3)) '(0 1 2 3))
             (list (two-node-graph 15) '(0 1)))))
    (test-case "projected prefix survives one support withdrawal but not the last"
      (let* ((edges '((0 1) (1 1) (1 3) (0 2) (2 2) (2 3)))
             (suffix '((0 0) (1 1) (2 2) (3 3)))
             (session (relational-open-program-session (declaration edges suffix 'projected)))
             (old (relational-program-session-run session)))
        (let ((full (gerbil-ascent-evaluate-program (declaration edges suffix #t)))
              (compact (gerbil-ascent-evaluate-program (declaration edges suffix 'projected))))
          ;; Two different internal witnesses collapse to one endpoint row.
          ;; Query equality therefore cannot certify preservation of supports.
          (check-equal? (length (filter (lambda (row) (and (= (car row) 0) (= (cadddr row) 3)))
                                       ((.ref full 'rows-of) 'prefix))) 2)
          (check-equal? (length (filter (lambda (row) (equal? row '(0 3)))
                                       ((.ref compact 'rows-of) 'prefix))) 1))
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
