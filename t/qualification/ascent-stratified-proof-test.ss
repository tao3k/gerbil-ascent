;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-candidate-digest
                 reasoning-receipt-stratified
                 reasoning-stratified-evidence-status
                 reasoning-stratified-evidence-finite
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt)
        (only-in :gerbil-ascent/candidate/funs
                 candidate-same-row-set?)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-finite-evidence finite-evidence-closure)
        (only-in :gerbil-ascent/candidate/stratified-proof
                 candidate-verify-stratified-proof)
        (only-in :gerbil-ascent/candidate/stratified-producer
                 candidate-produce-stratified-proof)
        (rename-in (only-in :gerbil-ascent/t/performance/stratified-model/reference-producer
                           candidate-produce-stratified-proof)
                   (candidate-produce-stratified-proof old-produce))
        (rename-in (only-in :gerbil-ascent/t/performance/stratified-model/reference-proof
                           candidate-verify-stratified-proof)
                   (candidate-verify-stratified-proof old-verify)))

(export ascent-stratified-proof-test)

(def (snapshot generation)
  (reasoning-source-snapshot
   'stratified-proof generation
   '((edge 2 ((1 2) (1 3)))
     (blocked 2 ((1 3)))
     (weight 2 ((2 4) (3 6)))
     (root 1 ((1) (2))))))

(def program
  '(candidate
     (relation allowed 2)
     (relation weighted 2)
     (relation summary 2)
     (rule (allowed ?x ?y) (edge ?x ?y)
           (not (blocked ?x ?y)))
     (rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
           (compute ?v (+ ?w ?w)))
     (rule (summary ?r ?n) (root ?r)
           (reduce ?n (count) (weighted ?r ?v)))
     (query summary 1 ?n)
     (limits 16 64 128)))

(def proof
  '(stratified-proof-v1
     ((source edge (1 2) 1 ())
      (rule allowed (1 2) 4 ((atom 0) (not)))
      (source weight (2 4) 1 ())
      (rule weighted (1 8) 5 ((atom 1) (atom 2) (fixed)))
      (source root (1) 1 ())
      (rule summary (1 1) 6 ((atom 4) (reduce (3)))))
     (5)))

(def (copy-pairs datum)
  (if (pair? datum)
    (cons (copy-pairs (car datum)) (copy-pairs (cdr datum)))
    datum))

(def possible-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))

(def stratified-graph-program
  '(candidate
     (relation path 2)
     (relation allowed 2)
     (relation total 2)
     (rule (path ?x ?y) (edge ?x ?y))
     (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
     (rule (allowed ?x ?y) (path ?x ?y)
           (not (blocked ?x ?y)))
     (rule (total ?r ?n) (root ?r)
           (reduce ?n (count) (allowed ?r ?y)))
     (query total 0 ?n)
     (limits 8 32 64)))

(def model-study-program
  '(candidate
     (relation path 2)
     (relation allowed 2)
     (relation weighted 2)
     (relation summary 2)
     (rule (path ?x ?y) (edge ?x ?y))
     (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
     (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
     (rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
           (where (even? ?w)) (compute ?v (+ ?w ?w)))
     (rule (summary ?r ?n) (root ?r)
           (reduce ?n (count) (weighted ?r ?v)))
     (query summary 1 ?n)
     (limits 16 64 128)))

(def (mask-edges mask)
  (let loop ((remaining possible-edges) (bit 1) (rows []))
    (if (null? remaining)
      (reverse rows)
      (loop (cdr remaining) (* bit 2)
            (if (zero? (bitwise-and mask bit)) rows
              (cons (car remaining) rows))))))

(def (case-values)
  (let* ((source (snapshot 1))
         (receipt (reasoning-attempt source program))
         (spec (candidate-inspect source program))
         (digest (reasoning-receipt-candidate-digest receipt))
         (status (reasoning-receipt-status receipt))
         (rows (reasoning-receipt-rows receipt))
         (finite (candidate-finite-evidence
                  source spec digest status rows 5000)))
    (values source spec digest status rows finite)))

(def (verify source spec digest status rows finite witness (budget 5000))
  (candidate-verify-stratified-proof
   source spec digest status rows finite 5000 witness budget))

(def (reducer-program operator root)
  (list 'candidate
        '(relation total 2)
        (list 'rule '(total ?r ?v) '(root ?r)
              (list 'reduce '?v
                    (if (eq? operator 'count)
                      '(count) (list operator '?w))
                    '(weight ?r ?w)))
        (list 'query 'total root '?v)
        '(limits 8 16 32)))

(def (reducer-proof operator root value)
  (let* ((base
          (list (list 'source 'root (list root) root '())))
         (weight-nodes
          (if (= root 1)
            '((source weight (1 4) 1 ())
              (source weight (1 6) 2 ()))
            '()))
         (refs (if (= root 1) '(1 2) '()))
         (rule-node
          (list 'rule 'total (list root value) 2
                (list '(atom 0) (list 'reduce refs)))))
    (list 'stratified-proof-v1
          (append base weight-nodes (list rule-node))
          (list (+ 1 (length weight-nodes))))))

(def (reducer-case operator root expected witness)
  (let* ((source
          (reasoning-source-snapshot
           'reducers 1
           '((root 1 ((1) (2)))
             (weight 2 ((1 4) (1 6))))))
         (datum (reducer-program operator root))
         (receipt (reasoning-attempt source datum))
         (spec (candidate-inspect source datum))
         (digest (reasoning-receipt-candidate-digest receipt))
         (status (reasoning-receipt-status receipt))
         (rows (reasoning-receipt-rows receipt))
         (finite (candidate-finite-evidence
                  source spec digest status rows 5000)))
    (check-equal? status 'complete)
    (check-equal? rows (list (list root expected)))
    (check-equal? (verify source spec digest status rows finite witness)
                  'valid)
    (let-values (((produced-status produced)
                  (candidate-produce-stratified-proof
                   source spec digest status rows finite 5000 5000)))
      (check-equal? produced-status 'complete)
      (check-equal? (verify source spec digest status rows finite produced)
                    'valid))))

(def ascent-stratified-proof-test
  (test-suite "bounded stratified derivation checker"
    (test-case "indexed closure preserves exact ordered proofs and both budget boundaries"
      (let* ((source (reasoning-source-snapshot 'indexed-proof 1
                       '((s 1 ((#f) (a) (a) (3))))))
             (datum '(candidate (relation p 1) (rule (p ?x) (s ?x))
                               (query p ?x) (limits 16 64 128)))
             (receipt (reasoning-attempt source datum))
             (spec (candidate-inspect source datum))
             (digest (reasoning-receipt-candidate-digest receipt))
             (rows (reasoning-receipt-rows receipt))
             (finite (candidate-finite-evidence source spec digest 'complete rows 5000)))
        (let-values (((status proof) (candidate-produce-stratified-proof
                                     source spec digest 'complete rows finite 5000 5000))
                     ((old-status old-proof) (old-produce
                                             source spec digest 'complete rows finite 5000 5000)))
          (check-equal? status 'complete)
          (check-equal? (list status proof) (list old-status old-proof))
          (for-each
           (lambda (budget)
             (let-values (((current-status current-proof) (candidate-produce-stratified-proof
                                source spec digest 'complete rows finite 5000 budget))
                          ((prior-status prior-proof) (old-produce
                                source spec digest 'complete rows finite 5000 budget)))
               (check-equal? (list current-status current-proof) (list prior-status prior-proof)))
             (check-equal? (candidate-verify-stratified-proof
                             source spec digest 'complete rows finite 5000 proof budget)
                           (old-verify source spec digest 'complete rows finite 5000 proof budget))
             (let-values (((current-status current-proof) (candidate-produce-stratified-proof
                                source spec digest 'complete rows finite budget 5000))
                          ((prior-status prior-proof) (old-produce
                                source spec digest 'complete rows finite budget 5000)))
               (check-equal? (list current-status current-proof) (list prior-status prior-proof))))
           (iota 80 1))
          (let (duplicate-position (copy-pairs proof))
            (set-car! (cdddr (cadr (cadr duplicate-position))) 3)
            (check-equal? (candidate-verify-stratified-proof
                            source spec digest 'complete rows finite 5000 duplicate-position 5000) 'valid)
            (check-equal? (old-verify
                            source spec digest 'complete rows finite 5000 duplicate-position 5000) 'valid))
          (let (mutated (copy-pairs proof))
            ;; A duplicate source occurrence is a valid position. The same
            ;; row at a different, unequal position must be rejected by both.
            (set-car! (cdddr (car (cadr mutated))) 4)
            (check-equal? (candidate-verify-stratified-proof
                            source spec digest 'complete rows finite 5000 mutated 5000) 'invalid)
            (check-equal? (old-verify source spec digest 'complete rows finite 5000 mutated 5000) 'invalid)))))
    (test-case "hypothetical fact support is bound to its clause label"
      (let* ((source (snapshot 1))
             (datum
              '(candidate
                 (relation allowed 2)
                 (fact edge 1 4)
                 (rule (allowed ?x ?y) (edge ?x ?y)
                       (not (blocked ?x ?y)))
                 (query allowed 1 4)
                 (limits 16 64 128)))
             (receipt (reasoning-attempt source datum))
             (spec (candidate-inspect source datum))
             (digest (reasoning-receipt-candidate-digest receipt))
             (status (reasoning-receipt-status receipt))
             (rows (reasoning-receipt-rows receipt))
             (finite (candidate-finite-evidence
                      source spec digest status rows 5000))
             (witness
              '(stratified-proof-v1
                 ((candidate edge (1 4) 2 ())
                  (rule allowed (1 4) 3 ((atom 0) (not))))
                 (1))))
        (check-equal? rows '((1 4)))
        (check-equal? (verify source spec digest status rows finite witness)
                      'valid)
        (let-values (((produced-status produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 5000 5000)))
          (check-equal? produced-status 'complete)
          (check-equal? (verify source spec digest status rows finite produced)
                        'valid))
        (let (changed (copy-pairs witness))
          (set-car! (cdddr (car (cadr changed))) 99)
          (check-equal? (verify source spec digest status rows finite changed)
                        'invalid))))
    (test-case "founded negation, computation and count rule instances"
      (let-values (((source spec digest status rows finite)
                    (case-values)))
        (check-equal? status 'complete)
        (check-equal? rows '((1 1)))
        (check-equal? (verify source spec digest status rows finite proof)
                      'valid)
        (displayln "STRATIFIED-PROOF-CHECKED direct-witness") (force-output)
        (let-values (((produced-status produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 5000 5000)))
          (check-equal? produced-status 'complete)
          (check-equal? (verify source spec digest status rows finite produced)
                        'valid)
          (displayln "STRATIFIED-PROOF-CHECKED produced-witness") (force-output))
        (let-values (((produced-status produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 5000 1)))
          (check-equal? produced-status 'bounded)
          (check-equal? produced []))))
    (test-case "recursive producer roots have founded earlier support"
      (let* ((source
              (reasoning-source-snapshot
               'recursive-proof 1
               '((edge 2 ((0 1) (1 2) (2 0))))))
             (datum
              '(candidate
                 (relation path 2)
                 (rule (path ?x ?y) (edge ?x ?y))
                 (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                 (query path 0 ?y)
                 (limits 16 64 128)))
             (receipt (reasoning-attempt source datum))
             (spec (candidate-inspect source datum))
             (digest (reasoning-receipt-candidate-digest receipt))
             (status (reasoning-receipt-status receipt))
             (rows (reasoning-receipt-rows receipt))
             (finite (candidate-finite-evidence
                      source spec digest status rows 20000)))
        (check-equal? status 'complete)
        (let-values (((produced-status produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 20000 20000)))
          (check-equal? produced-status 'complete)
          (check-equal?
           (verify source spec digest status rows finite produced 20000)
           'valid))))
    (test-case "producer handles comparison, identity and negative wildcard"
      (let* ((source
              (reasoning-source-snapshot
               'fixed-proof 1
               '((edge 2 ((1 2) (1 3)))
                 (blocked 2 ((3 0))))))
             (datum
              '(candidate
                 (relation selected 2)
                 (rule (selected ?x ?v) (edge ?x ?y)
                       (where (< ?x ?y))
                       (compute ?v (identity ?y))
                       (not (blocked ?y ?_)))
                 (query selected 1 ?v)
                 (limits 16 64 128)))
             (receipt (reasoning-attempt source datum))
             (spec (candidate-inspect source datum))
             (digest (reasoning-receipt-candidate-digest receipt))
             (status (reasoning-receipt-status receipt))
             (rows (reasoning-receipt-rows receipt))
             (finite (candidate-finite-evidence
                      source spec digest status rows 5000)))
        (check-equal? status 'complete)
        (check-equal? rows '((1 2)))
        (let-values (((produced-status produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 5000 5000)))
          (check-equal? produced-status 'complete)
          (check-equal?
           (verify source spec digest status rows finite produced)
           'valid))))
    (test-case "all sixty-four finite graphs have checked producer roots"
      (for-each
       (lambda (mask)
         (let* ((source
                 (reasoning-source-snapshot
                  'recursive-corpus mask
                  (list (list 'edge 2 (mask-edges mask)))))
                (datum
                 '(candidate
                    (relation path 2)
                    (rule (path ?x ?y) (edge ?x ?y))
                    (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                    (query path 0 ?y)
                    (limits 16 64 128)))
                (receipt (reasoning-attempt source datum))
                (spec (candidate-inspect source datum))
                (digest (reasoning-receipt-candidate-digest receipt))
                (status (reasoning-receipt-status receipt))
                (rows (reasoning-receipt-rows receipt))
                (finite
                 (candidate-finite-evidence
                  source spec digest status rows 20000)))
           (check-equal? status 'complete)
           (let-values (((produced-status produced)
                         (candidate-produce-stratified-proof
                          source spec digest status rows finite
                          20000 20000)))
             (if (null? rows)
               (check-equal? produced-status 'unsupported)
               (begin
                 (check-equal? produced-status 'complete)
                 (check-equal?
                  (verify source spec digest status rows finite
                          produced 20000)
                  'valid))))))
       (iota 64)))
    (test-case "recursive strata track source correction and distinct support"
      ;; Edges give paths 0->1 and 0->2. Blocking 0->2 leaves one
      ;; allowed target; removing that block leaves two. Repeating an
      ;; edge must not turn the count into three.
      (let* ((first
              (reasoning-source-snapshot
               'stratified-change 1
               '((edge 2 ((0 1) (1 2)))
                 (blocked 2 ((0 2)))
                 (root 1 ((0))))))
             (changed
              (reasoning-source-snapshot
               'stratified-change 2
               '((edge 2 ((0 1) (1 2)))
                 (blocked 2 ())
                 (root 1 ((0))))))
             (repeated
              (reasoning-source-snapshot
               'stratified-change 3
               '((edge 2 ((0 1) (0 1) (1 2)))
                 (blocked 2 ())
                 (root 1 ((0))))))
             (old-receipt
              (reasoning-attempt first stratified-graph-program))
             (old-spec (candidate-inspect first stratified-graph-program))
             (old-digest
              (reasoning-receipt-candidate-digest old-receipt))
             (old-rows (reasoning-receipt-rows old-receipt))
             (old-finite
              (candidate-finite-evidence
               first old-spec old-digest 'complete old-rows 20000)))
        (check-equal? old-rows '((0 1)))
        (for-each
         (lambda (source expected)
           (let* ((receipt (reasoning-attempt source stratified-graph-program))
                  (spec (candidate-inspect source stratified-graph-program))
                  (digest (reasoning-receipt-candidate-digest receipt))
                  (status (reasoning-receipt-status receipt))
                  (rows (reasoning-receipt-rows receipt))
                  (finite
                   (candidate-finite-evidence
                    source spec digest status rows 20000)))
             (check-equal? status 'complete)
             (check-equal? rows expected)
             (let-values (((produced-status produced)
                           (candidate-produce-stratified-proof
                            source spec digest status rows finite
                            20000 20000)))
               (check-equal? produced-status 'complete)
               (check-equal?
                (verify source spec digest status rows finite
                        produced 20000)
                'valid))))
         (list first changed repeated)
         '(((0 1)) ((0 2)) ((0 2))))
        (let-values (((verdict produced)
                      (candidate-produce-stratified-proof
                       changed old-spec old-digest 'complete old-rows
                       old-finite 20000 20000)))
          (check-equal? verdict 'invalid)
          (check-equal? produced []))))
    (test-case "stale finite certificate cannot produce a proof"
      (let-values (((source spec digest status rows finite)
                    (case-values)))
        (let-values (((produced-status produced)
                      (candidate-produce-stratified-proof
                       (snapshot 2) spec digest status rows finite
                       5000 5000)))
          (check-equal? produced-status 'invalid)
          (check-equal? produced []))))
    (test-case "finite replay and proof search expose separate budget caps"
      (let-values (((source spec digest status rows finite)
                    (case-values)))
        (let-values (((verdict produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 1 5000)))
          (check-equal? verdict 'bounded)
          (check-equal? produced []))
        (let-values (((verdict produced)
                      (candidate-produce-stratified-proof
                       source spec digest status rows finite 5000 1)))
          (check-equal? verdict 'bounded)
          (check-equal? produced []))))
    (test-case "repeated, omitted and forward group support fail"
      (let-values (((source spec digest status rows finite)
                    (case-values)))
        (let (omitted (copy-pairs proof))
          (set-car! (cdr (list-ref (list-ref (cadr omitted) 5) 4))
                    '(reduce ()))
          (check-equal? (verify source spec digest status rows finite omitted)
                        'invalid))
        (let (forward (copy-pairs proof))
          (set-car! (list-ref (list-ref (cadr forward) 1) 4)
                    '(atom 1))
          (check-equal? (verify source spec digest status rows finite forward)
                        'invalid))
        (let (duplicate (copy-pairs proof))
          (set-car! (cdr (list-ref (list-ref (cadr duplicate) 5) 4))
                    '(reduce (3 3)))
          (check-equal? (verify source spec digest status rows finite duplicate)
                        'invalid))
        (let (wrong-negation (copy-pairs proof))
          (set-car! (cddr (list-ref (cadr wrong-negation) 1)) '(1 3))
          (check-equal?
           (verify source spec digest status rows finite wrong-negation)
           'invalid))))
    (test-case "changed snapshot, closure and proof budget do not certify"
      (let-values (((source spec digest status rows finite)
                    (case-values)))
        (check-equal? (verify (snapshot 2) spec digest status rows finite proof)
                      'invalid)
        (check-equal? (verify source spec digest status rows finite proof 1)
                      'bounded)
        (check-equal? (verify source spec 'other status rows finite proof)
                      'invalid)
        (let (wrong-root (copy-pairs proof))
          (set-car! (caddr wrong-root) 0)
          (check-equal? (verify source spec digest status rows finite wrong-root)
                        'invalid))
        (let (cyclic (list 'stratified-proof-v1 [] []))
          (set-car! (cdr cyclic) cyclic)
          (check-equal? (verify source spec digest status rows finite cyclic)
                        'invalid))
        (set-car! (cddr (assq 'allowed (finite-evidence-closure finite)))
                  '((1 3)))
        (check-equal? (verify source spec digest status rows finite proof)
                      'invalid)))
    (test-case "model-study input agrees with Rust and finite expectations"
      ;; The POO Flow frozen task uses exactly these three source states.
      ;; Blocking (1,3) leaves one distinct weighted row; removing the
      ;; block gives two; repeating an edge does not change the count.
      (let* ((first
              (reasoning-source-snapshot
               'study-negation-count 1
               '((edge 2 ((1 2) (2 3)))
                 (blocked 2 ((1 3)))
                 (weight 2 ((2 4) (3 6)))
                 (root 1 ((1))))))
             (changed
              (reasoning-source-snapshot
               'study-negation-count 2
               '((edge 2 ((1 2) (2 3)))
                 (blocked 2 ())
                 (weight 2 ((2 4) (3 6)))
                 (root 1 ((1))))))
             (repeated
              (reasoning-source-snapshot
               'study-negation-count 3
               '((edge 2 ((1 2) (1 2) (2 3)))
                 (blocked 2 ())
                 (weight 2 ((2 4) (3 6)))
                 (root 1 ((1))))))
             (old (reasoning-attempt first model-study-program 100000 20000)))
        (for-each
         (lambda (source expected allowed weighted)
           (let* ((receipt
                   (reasoning-attempt source model-study-program
                                      100000 20000))
                  (evidence (reasoning-receipt-stratified receipt))
                  (closure
                   (finite-evidence-closure
                    (reasoning-stratified-evidence-finite evidence))))
             (check-equal? (reasoning-receipt-status receipt) 'complete)
             (check-equal? (reasoning-receipt-rows receipt) expected)
             (check-equal?
              (candidate-same-row-set? (caddr (assq 'path closure))
                                       '((1 2) (1 3) (2 3)))
              #t)
             (check-equal?
              (candidate-same-row-set? (caddr (assq 'allowed closure))
                                       allowed)
              #t)
             (check-equal?
              (candidate-same-row-set? (caddr (assq 'weighted closure))
                                       weighted)
              #t)
             (check-equal? (reasoning-stratified-evidence-status evidence)
                           'complete)
             (check-equal?
              (reasoning-verify-finite-receipt
               receipt source model-study-program 20000)
              'valid)
             (check-equal?
              (reasoning-verify-stratified-receipt
               receipt source model-study-program 20000)
              'valid)))
         (list first changed repeated)
         '(((1 1)) ((1 2)) ((1 2)))
         '(((1 2) (2 3))
           ((1 2) (1 3) (2 3))
           ((1 2) (1 3) (2 3)))
         '(((1 8) (2 12))
           ((1 8) (1 12) (2 12))
           ((1 8) (1 12) (2 12))))
        (check-equal?
         (reasoning-verify-stratified-receipt
          old changed model-study-program 20000)
         'invalid)))
    (test-case "all reducers require an exact contributing group"
      (for-each
       (lambda (operator value)
         (reducer-case operator 1 value
                       (reducer-proof operator 1 value)))
       '(count sum min max) '(2 10 4 6))
      (reducer-case 'count 2 0 (reducer-proof 'count 2 0))
      (reducer-case 'sum 2 0 (reducer-proof 'sum 2 0)))))
