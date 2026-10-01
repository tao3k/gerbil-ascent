;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/types
                 make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-snapshot-digest
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-candidate-digest
                 reasoning-receipt-proof)
        (only-in :gerbil-ascent/candidate/provenance
                 candidate-positive-proof candidate-verify-positive-proof
                 positive-proof-status
                 positive-proof-snapshot-digest
                 positive-proof-candidate-digest positive-proof-query
                 positive-proof-nodes positive-proof-roots
                 proof-node-id proof-node-kind proof-node-relation
                 proof-node-row proof-node-label proof-node-inputs))

(export ascent-positive-provenance-test)

(def (graph-spec (extra-facts []))
  (make-reasoning-candidate
   '((path . 2))
   extra-facts
   (list
    (vector '(path ?x ?y) '((edge ?x ?y)) 3)
    (vector '(path ?x ?z)
            '((path ?x ?y) (edge ?y ?z)) 4))
   (vector '(path 1 3) 5)
   '(8 16 32)))

(def (graph-source)
  (reasoning-source-snapshot
   'graph 7 '((edge 2 ((1 2))))))

(def ascent-positive-provenance-test
  (test-suite "bounded positive provenance"
    (test-case "public attempt binds native completion to replayable proof"
      (let* ((snapshot
              (reasoning-source-snapshot
               'graph 8 '((edge 2 ((1 2))))))
             (datum
              '(candidate
                 (relation path 2)
                 (fact edge 2 3)
                 (rule (path ?x ?y) (edge ?x ?y))
                 (rule (path ?x ?z)
                       (path ?x ?y) (edge ?y ?z))
                 (query path 1 3)
                 (limits 8 16 32)))
             (receipt (reasoning-attempt snapshot datum))
             (proof (reasoning-receipt-proof receipt))
             (spec (candidate-inspect snapshot datum)))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-receipt-rows receipt) '((1 3)))
        (check-equal? (positive-proof-status proof) 'complete)
        (check-equal?
         (candidate-verify-positive-proof
          snapshot spec (reasoning-receipt-candidate-digest receipt)
          (reasoning-receipt-status receipt)
          (reasoning-receipt-rows receipt) proof 32)
         #t)
        (let* ((bounded (reasoning-attempt snapshot datum 1))
               (bounded-proof (reasoning-receipt-proof bounded)))
          (check-equal? (reasoning-receipt-status bounded) 'complete)
          (check-equal? (positive-proof-status bounded-proof) 'bounded))))
    (test-case "recursive rule DAG separates observed and candidate facts"
      (let* ((proof
              (candidate-positive-proof
               (graph-source)
               (graph-spec (list (vector 'edge '(2 3) 6)))
               'candidate-digest 'complete '((1 3)) 200))
             (nodes (positive-proof-nodes proof))
             (last (list-ref nodes 4)))
        (check-equal? (positive-proof-status proof) 'complete)
        (check-equal? (positive-proof-snapshot-digest proof)
                      (reasoning-snapshot-digest (graph-source)))
        (check-equal? (positive-proof-candidate-digest proof)
                      'candidate-digest)
        (check-equal? (positive-proof-query proof) '(path 1 3))
        (check-equal? (length nodes) 5)
        (check-equal? (map proof-node-id nodes) '(0 1 2 3 4))
        (check-equal? (proof-node-kind (car nodes)) 'source)
        (check-equal? (proof-node-label (car nodes)) 1)
        (check-equal? (proof-node-kind (cadr nodes)) 'candidate)
        (check-equal? (proof-node-label (cadr nodes)) 6)
        (check-equal? (proof-node-kind last) 'rule)
        (check-equal? (proof-node-relation last) 'path)
        (check-equal? (proof-node-row last) '(1 3))
        (check-equal? (proof-node-label last) 4)
        (check-equal? (proof-node-inputs last) '(2 1))
        (check-equal? (positive-proof-roots proof) '(4))
        (check-equal?
         (candidate-verify-positive-proof
          (graph-source)
          (graph-spec (list (vector 'edge '(2 3) 6)))
          'candidate-digest 'complete '((1 3)) proof 20)
         #t)
        (check-equal?
         (candidate-verify-positive-proof
          (graph-source)
          (graph-spec (list (vector 'edge '(2 3) 6)))
          'other-digest 'complete '((1 3)) proof 20)
         #f)
        (set-car! (proof-node-row last) 99)
        (check-equal?
         (candidate-verify-positive-proof
          (graph-source)
          (graph-spec (list (vector 'edge '(2 3) 6)))
          'candidate-digest 'complete '((1 3)) proof 20)
         #f)))
    (test-case "wrong native answer and insufficient work cannot prove"
      (let ((spec (graph-spec (list (vector 'edge '(2 3) 6)))))
        (check-equal?
         (positive-proof-status
          (candidate-positive-proof
           (graph-source) spec 'candidate-digest 'complete '((1 4)) 200))
         'unsupported)
        (check-equal?
         (positive-proof-status
          (candidate-positive-proof
           (graph-source) spec 'candidate-digest 'unknown '((1 3)) 200))
         'unsupported)
        (let (bounded
              (candidate-positive-proof
               (graph-source) spec 'candidate-digest 'complete '((1 3)) 1))
          (check-equal? (positive-proof-status bounded) 'bounded)
          (check-equal? (positive-proof-nodes bounded) '()))))
    (test-case "repeated variables, multi-source join and derived cap"
      (let* ((snapshot
              (reasoning-source-snapshot
               'family 3
               '((parent 2 ((1 2) (2 3) (1 4)))
                 (alias 2 ((2 2) (4 5))))))
             (spec
              (make-reasoning-candidate
               '((selected . 2)) []
               (list (vector '(selected ?x ?z)
                             '((parent ?x ?y)
                               (alias ?y ?y)
                               (parent ?y ?z))
                             3))
               (vector '(selected 1 ?z) 4) '(16 8 32)))
             (proof
              (candidate-positive-proof
               snapshot spec 'program-digest 'complete '((1 3)) 200))
             (nodes (positive-proof-nodes proof)))
        (check-equal? (positive-proof-status proof) 'complete)
        (check-equal? (positive-proof-roots proof) '(5))
        (check-equal? (proof-node-inputs (list-ref nodes 5)) '(0 3 1))
        (check-equal?
         (positive-proof-status
          (candidate-positive-proof
           snapshot
           (make-reasoning-candidate
            '((selected . 2)) []
            (list (vector '(selected ?x ?y)
                          '((parent ?x ?y)) 3))
            (vector '(selected 1 ?z) 4) '(16 1 32))
           'program-digest 'complete '((1 2) (1 4)) 200))
         'bounded)))
    (test-case "absence and nonpositive clauses have no proof claim"
      (let ((absent
             (candidate-positive-proof
              (graph-source) (graph-spec) 'candidate-digest 'complete '() 200))
            (negated
             (make-reasoning-candidate
              '((allowed . 2)) []
              (list (vector '(allowed ?x ?y)
                            '((edge ?x ?y) (not (blocked ?x ?y))) 3))
              (vector '(allowed 1 2) 4) '(8 16 32))))
        (check-equal? (positive-proof-status absent) 'unsupported)
        (check-equal?
         (positive-proof-status
          (candidate-positive-proof
           (graph-source) negated 'candidate-digest 'complete '((1 2)) 200))
         'unsupported)))))
