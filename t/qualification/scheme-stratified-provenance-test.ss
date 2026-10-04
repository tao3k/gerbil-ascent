;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows reasoning-receipt-candidate-digest)
        (only-in :gerbil-ascent/candidate/finite-evidence candidate-finite-evidence finite-evidence-status)
        (only-in :gerbil-ascent/candidate/stratified-provenance
                 candidate-stratified-provenance candidate-verify-stratified-provenance
                 stratified-provenance-status stratified-provenance-nodes
                 stratified-provenance-edges stratified-provenance-roots))
(export scheme-stratified-provenance-test)
(def (prepared snapshot datum)
  (let* ((receipt (reasoning-attempt snapshot datum))
         (spec (candidate-inspect snapshot datum))
         (digest (reasoning-receipt-candidate-digest receipt)) (rows (reasoning-receipt-rows receipt))
         (certificate (candidate-finite-evidence snapshot spec digest 'complete rows 20000)))
    (check-equal? (reasoning-receipt-status receipt) 'complete)
    (check-equal? (finite-evidence-status certificate) 'complete)
    (values spec digest rows certificate)))
(def (graph snapshot datum expected)
  (let-values (((spec digest rows certificate) (prepared snapshot datum)))
    (check-equal? rows expected)
    (let (result (candidate-stratified-provenance snapshot spec digest 'complete rows certificate 20000 20000 4096))
      (check-equal? (stratified-provenance-status result) 'complete)
      (check-equal? (candidate-verify-stratified-provenance snapshot spec digest 'complete rows certificate
                                                         20000 result 20000 4096) 'valid)
      result)))
(def recursive '(candidate (relation p 1) (rule (p ?x) (s ?x)) (rule (p ?x) (p ?x))
                           (query p ?x) (limits 16 64 128)))
(def (stratified-snapshot generation)
  (reasoning-source-snapshot 'stratified-graph generation
   '((edge 2 ((1 2) (2 3))) (blocked 2 ((1 3))) (weight 2 ((2 4) (3 6))) (root 1 ((1))))))
(def stratified
  '(candidate (relation path 2) (relation allowed 2) (relation weighted 2) (relation summary 2)
    (rule (path ?x ?y) (edge ?x ?y)) (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
    (rule (path ?x ?y) (path ?x ?y))
    (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
    (rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w) (where (even? ?w)) (compute ?v (+ ?w ?w)))
    (rule (summary ?r ?n) (root ?r) (reduce ?n (count) (weighted ?r ?v)))
    (query summary ?r ?n) (limits 16 64 128)))
(def (reduce-program mode)
  (list 'candidate '(relation total 2)
        (list 'rule '(total ?r ?n) '(root ?r)
              (list 'reduce '?n (if (eq? mode 'count) '(count) (list mode '?v)) '(weight ?r ?v)))
        '(query total ?r ?n) '(limits 16 64 128)))
(def six-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def (mask-edges mask)
  (filter-map (lambda (edge i) (and (odd? (quotient mask (expt 2 i))) edge)) six-edges (iota 6)))
(def (matrix edges)
  (let (table (make-vector 9 #f))
    (for-each (lambda (edge) (vector-set! table (+ (* 3 (car edge)) (cadr edge)) #t)) edges)
    (for-each (lambda (k) (for-each (lambda (i) (for-each (lambda (j)
      (when (and (vector-ref table (+ (* 3 i) k)) (vector-ref table (+ (* 3 k) j)))
        (vector-set! table (+ (* 3 i) j) #t))) (iota 3))) (iota 3))) (iota 3))
    (filter-map (lambda (i) (and (vector-ref table i) (list (quotient i 3) (modulo i 3)))) (iota 9))))

(def scheme-stratified-provenance-test
  (test-suite "Complete stratified recursive derivation graphs"
    (test-case "all duplicate-source and self-cycle alternatives remain explicit"
      (let (result (graph (reasoning-source-snapshot 'duplicates 1 '((s 1 ((1) (1))))) recursive '((1))))
        (check-equal? (length (stratified-provenance-nodes result)) 2)
        (check-equal? (length (stratified-provenance-edges result)) 4)
        (check-equal? (length (stratified-provenance-roots result)) 1)
        (check-equal? (ormap (lambda (edge)
                              (and (eq? (cadr edge) 'rule)
                                   (equal? (list-ref edge 3) (list (list 'atom (car edge))))))
                            (stratified-provenance-edges result)) #t)))
    (test-case "recursive equations retain exact absence and complete reduction group observations"
      (let (result (graph (stratified-snapshot 1) stratified '((1 1))))
        (check-equal? (length (stratified-provenance-nodes result)) 14)
        (check-equal? (length (stratified-provenance-edges result)) 17)
        (check-equal? (length (filter (lambda (edge)
                                      (ormap (lambda (w) (eq? (car w) 'not)) (list-ref edge 3)))
                                    (stratified-provenance-edges result))) 2)
        (check-equal? (length (filter (lambda (edge)
                                      (ormap (lambda (w) (and (eq? (car w) 'reduce) (= (length (cadr w)) 1)))
                                             (list-ref edge 3))) (stratified-provenance-edges result))) 1)))
    (test-case "empty queries yield a complete finite graph with no invented roots"
      (let* ((snapshot (reasoning-source-snapshot 'empty 1 '((s 1 ((1))))))
             (datum '(candidate (relation p 1) (rule (p ?x) (s ?x) (where (even? ?x)))
                                (query p ?x) (limits 16 64 128)))
             (result (graph snapshot datum '())))
        (check-equal? (length (stratified-provenance-nodes result)) 1)
        (check-equal? (stratified-provenance-roots result) '())))
    (test-case "count and sum record empty groups while min and max produce no row"
      (let (snapshot (reasoning-source-snapshot 'empty-group 1 '((root 1 ((1))) (weight 2 ()))))
        (for-each (lambda (mode)
          (let (result (graph snapshot (reduce-program mode) '((1 0))))
            (check-equal? (ormap (lambda (edge) (member '(reduce ()) (list-ref edge 3)))
                                (stratified-provenance-edges result)) '((reduce ()))))) '(count sum))
        (for-each (lambda (mode) (graph snapshot (reduce-program mode) '())) '(min max))))
    (test-case "incomplete, over-budget, missing and mutated alternatives cannot verify"
      (let ((snapshot (stratified-snapshot 1)) (other (stratified-snapshot 2)))
        (let-values (((spec digest rows cert) (prepared snapshot stratified)))
          (let (result (candidate-stratified-provenance snapshot spec digest 'complete rows cert 20000 20000 4096))
            (check-equal? (stratified-provenance-status
                          (candidate-stratified-provenance snapshot spec digest 'complete rows cert 20000 1 4096)) 'bounded)
            (check-equal? (stratified-provenance-status
                          (candidate-stratified-provenance snapshot spec digest 'complete rows cert 20000 20000 1)) 'bounded)
            (check-equal? (candidate-verify-stratified-provenance snapshot spec digest 'bounded rows cert
                                                               20000 result 20000 4096) 'invalid)
            (let-values (((other-spec other-digest other-rows other-cert) (prepared other stratified)))
              (check-equal? (candidate-verify-stratified-provenance other other-spec other-digest 'complete other-rows
                                                                 other-cert 20000 result 20000 4096) 'invalid))
            (let (missing (candidate-stratified-provenance snapshot spec digest 'complete rows cert 20000 20000 4096))
              (set-cdr! (stratified-provenance-edges missing) (cddr (stratified-provenance-edges missing)))
              (check-equal? (candidate-verify-stratified-provenance snapshot spec digest 'complete rows cert
                                                                 20000 missing 20000 4096) 'invalid))
            (let (cyclic (candidate-stratified-provenance snapshot spec digest 'complete rows cert 20000 20000 4096))
              (set-cdr! (stratified-provenance-edges cyclic) (stratified-provenance-edges cyclic))
              (check-equal? (candidate-verify-stratified-provenance snapshot spec digest 'complete rows cert
                                                                 20000 cyclic 20000 4096) 'invalid))
            (set-car! (stratified-provenance-roots result) 4095)
            (check-equal? (candidate-verify-stratified-provenance snapshot spec digest 'complete rows cert
                                                               20000 result 20000 4096) 'invalid)))))
    (test-case "negation observations preserve wildcard patterns rather than inventing bindings"
      (let* ((snapshot (reasoning-source-snapshot 'wildcard 1 '((s 1 ((1))) (blocked 2 ()))))
             (datum '(candidate (relation p 1) (rule (p ?x) (s ?x) (not (blocked ?x ?_)))
                                (query p ?x) (limits 16 64 128)))
             (result (graph snapshot datum '((1)))))
        (check-equal? (ormap (lambda (edge) (and (member '(not blocked (1 ?_)) (list-ref edge 3)) #t))
                            (stratified-provenance-edges result)) #t)))
    (test-case "all 64 finite graphs have every independently counted grounded alternative"
      (for-each (lambda (mask)
        (let* ((edges (mask-edges mask)) (expected (matrix edges))
               (snapshot (reasoning-source-snapshot 'corpus mask (list (list 'edge 2 edges))))
               (datum '(candidate (relation path 2) (rule (path ?x ?y) (edge ?x ?y))
                                  (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                                  (query path ?x ?y) (limits 16 64 128))))
          (let-values (((spec digest rows cert) (prepared snapshot datum)))
            (check-equal? (length rows) (length expected))
            (for-each (lambda (row) (check-equal? (and (member row rows) #t) #t)) expected)
            (let ((result (candidate-stratified-provenance snapshot spec digest 'complete rows cert 20000 20000 4096))
                  (count (+ (* 2 (length edges))
                            (apply + 0 (map (lambda (row) (length (filter (lambda (edge) (= (cadr row) (car edge))) edges))) expected)))))
              (check-equal? (stratified-provenance-status result) 'complete)
              (check-equal? (length (stratified-provenance-edges result)) count)
              (check-equal? (candidate-verify-stratified-provenance snapshot spec digest 'complete rows cert
                                                                 20000 result 20000 4096) 'valid)
              (displayln "STRATIFIED-GRAPH-CHECKED " mask) (force-output))))) (iota 64)))))
