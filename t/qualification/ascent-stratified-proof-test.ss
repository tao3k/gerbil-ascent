;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-candidate-digest)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-finite-evidence finite-evidence-closure)
        (only-in :gerbil-ascent/candidate/stratified-proof
                 candidate-verify-stratified-proof))

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
                  'valid)))

(def ascent-stratified-proof-test
  (test-suite "bounded stratified derivation checker"
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
                      'valid)))
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
    (test-case "all reducers require an exact contributing group"
      (for-each
       (lambda (operator value)
         (reducer-case operator 1 value
                       (reducer-proof operator 1 value)))
       '(count sum min max) '(2 10 4 6))
      (reducer-case 'count 2 0 (reducer-proof 'count 2 0))
      (reducer-case 'sum 2 0 (reducer-proof 'sum 2 0)))))
