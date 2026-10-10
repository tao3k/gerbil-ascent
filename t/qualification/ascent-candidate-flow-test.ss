;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-construct-inert-program gerbil-ascent-variable gerbil-ascent-program gerbil-ascent-atom gerbil-ascent-rule)
        :gerbil-ascent/candidate/reasoning
        :gerbil-ascent/candidate/types
        :gerbil-ascent/t/performance/candidate-flow/fixture
        (prefix-in :gerbil-ascent/t/performance/candidate-flow/reference-reasoning old-))
(export ascent-candidate-flow-test)
(def (compare snapshot candidate (proof #f) (stratified #f))
  (let* ((old (old-reasoning-attempt snapshot candidate proof stratified))
         (new (reasoning-attempt snapshot candidate proof stratified)))
    (check-equal? (receipt-projection #f new) (receipt-projection #t old))
    new))
(def (diagnostic snapshot proposal code path)
  (let* ((receipt (compare snapshot proposal))
         (d (car (reasoning-receipt-diagnostics receipt))))
    (check-equal? (reasoning-receipt-status receipt) 'rejected)
    (check-equal? (reasoning-diagnostic-code d) code)
    (check-equal? (reasoning-diagnostic-path d) path)))
(def ascent-candidate-flow-test
  (test-suite "Candidate admission through receipt"
    (test-case "complete declaration and fact order against frozen consumers"
      (for-each (lambda (scenario)
        (let (input (candidate-flow-input scenario))
          (check-equal? (candidate-flow-workflow #f input) (candidate-flow-workflow #t input))))
        '(wide medium scope small empty)))
    (test-case "all directed three-node graphs preserve nonempty support and cut order"
      (let (possible '((0 0) (0 1) (0 2) (1 0) (1 1) (1 2) (2 0) (2 1) (2 2)))
        (for-each (lambda (mask)
          (let* ((edges (filter-map (lambda (edge bit)
                         (and (not (zero? (bitwise-and mask (arithmetic-shift 1 bit)))) edge))
                         possible (iota 9)))
                 (snapshot (reasoning-source-snapshot 'graph mask (list (list 'edge 2 edges)))))
            (compare snapshot (graph-proposal 0 2)))
          (displayln "GRAPH-MASKS-OK " (+ mask 1) "/512") (force-output)) (iota 512))))
    (test-case "inert construction checks its root and restores public validation"
      (check-exception (gerbil-ascent-construct-inert-program (lambda () (.o))) true)
      (check-exception (gerbil-ascent-program [] (list (.o)) 16 64 128) true)
      (check-exception (gerbil-ascent-variable 7) true)
      (check-exception
       (gerbil-ascent-construct-inert-program
        (lambda () (gerbil-ascent-program [] (list (.o)) 16 64 128))) true)
      (check-exception
       (gerbil-ascent-construct-inert-program
        (lambda ()
          (gerbil-ascent-program []
           (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (.o)))) []))
           16 64 128))) true)
      (check-exception (gerbil-ascent-atom 'out (list (.o))) true)
      (check-equal? (.ref (gerbil-ascent-variable (quote ?x)) (quote value)) (quote ?x)))
    (test-case "reflexive queries require nonempty support"
      (for-each
       (lambda (edges)
         (let* ((snapshot (reasoning-source-snapshot 'reflexive 0 (list (list 'edge 2 edges))))
                (receipt (compare snapshot (graph-proposal 0 0)))
                (evidence (reasoning-receipt-evidence receipt)))
           (check-equal? (reasoning-evidence-kind evidence)
                         (if (null? edges) 'unsupported 'witness))
           (when (pair? edges)
             (check-equal? (length (reasoning-evidence-support evidence)) (length edges)))))
       '(() ((0 0)) ((0 1) (1 0)))))
    (test-case "source-first witness ties and hypothetical duplicate occurrences"
      (let* ((snapshot (reasoning-source-snapshot 'ties 0 '((edge 2 ((0 2) (0 1) (2 3) (1 3) (0 2))))))
             (receipt (compare snapshot (graph-proposal 0 3 '((fact edge 0 3) (fact edge 0 3))))))
        (check-equal? (reasoning-evidence-support (reasoning-receipt-evidence receipt))
                      '((candidate 4 (0 3)))))
      (let* ((snapshot (reasoning-source-snapshot 'ties 0 '((edge 2 ((0 2) (0 1) (2 3) (1 3))))))
             (receipt (compare snapshot (graph-proposal 0 3 '((fact edge 0 1))))))
        (check-equal? (reasoning-evidence-support (reasoning-receipt-evidence receipt))
                      '((source 1 (0 2)) (source 3 (2 3))))))
    (test-case "exact integer node identity and disconnected components"
      (let* ((n (expt 2 80))
             (snapshot (reasoning-source-snapshot 'large 0
                         (list (list 'edge 2 (list (list n (+ n 1)) (list (+ n 1) (+ n 2)) '(0 1)))))))
        (check-equal? (reasoning-receipt-rows (compare snapshot (graph-proposal n (+ n 2))))
                      (list (list n (+ n 2))))))
    (test-case "schema authority and diagnostic precedence retain exact locations"
      (let (snapshot (reasoning-source-snapshot 'schema 0 '((input 0 (())))))
        (diagnostic snapshot '(candidate (relation input 1) (fact missing 1)
                                        (query missing 1) (limits 16 64 128))
                    'duplicate-relation '(relations))
        (diagnostic snapshot '(candidate (relation result 0) (fact result)
                                        (query result) (limits 16 64 128))
                    'fact-needs-source '(clause 2))
        (diagnostic snapshot '(candidate (relation result 0) (rule (input) (missing))
                                        (query result) (limits 16 64 128))
                    'rule-writes-source '(clause 2 head))
        (check-equal? (reasoning-receipt-rows
                       (compare snapshot '(candidate (relation result 0) (fact input)
                                                     (rule (result) (input)) (query result)
                                                     (limits 16 64 128)))) '(()))))
    (test-case "rule scopes preserve binding freshness and first missing input"
      (let (snapshot (reasoning-source-snapshot 'scope 0 '((input 1 ((4))))))
        (for-each (lambda (entry)
          (with ([body code path] entry)
            (diagnostic snapshot
              (list 'candidate '(relation result 1)
                    (cons 'rule (cons '(result ?x) body)) '(query result ?x) '(limits 16 64 128))
              code path)))
          '((((input ?x) (input ?x) (compute ?x (identity ?x))) duplicate-binding (clause 2 body 3))
            (((input ?x) (not (input ?y))) unsafe-negation (clause 2 body 2 term 1))
            (((input ?x) (where (< ?a ?b))) unbound-operator-input (clause 2 body 2 input 1))))
        (diagnostic snapshot '(candidate (relation result 1)
                               (rule (result ?x) (input ?x))
                               (rule (result ?x) (where (even? ?x)))
                               (query result ?x) (limits 16 64 128))
                    'unbound-operator-input '(clause 3 body 1 input 1))))
    (test-case "proof budgets and independent current-content verification"
      (let* ((snapshot (reasoning-source-snapshot 'proof 0 '((edge 2 ((0 1) (1 2))))))
             (proposal (graph-proposal 0 2)))
        (for-each (lambda (budget) (compare snapshot proposal budget budget)) '(1 100000))
        (let (receipt (compare snapshot proposal 100000 100000))
          (check-equal? (reasoning-verify-finite-receipt receipt snapshot proposal 100000) 'valid)
          (check-equal? (reasoning-verify-stratified-receipt receipt snapshot proposal 100000) 'valid)
          (set-car! (caddar (reasoning-snapshot-relations snapshot)) '(9 10))
          (check-equal? (reasoning-receipt-bound? receipt snapshot proposal) #f))))))
