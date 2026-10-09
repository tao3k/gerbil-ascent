;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-candidate-digest)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-finite-evidence candidate-verify-finite-evidence
                 finite-evidence-status finite-evidence-closure))

(export ascent-finite-evidence-test)

(def (source generation blocked)
  (reasoning-source-snapshot
   'finite-strata generation
   (list '(edge 2 ((1 2) (2 3)))
         (list 'blocked 2 blocked)
         '(weight 2 ((2 4) (3 6)))
         '(root 1 ((1))))))

(def (program query)
  (list 'candidate
        '(relation path 2)
        '(relation allowed 2)
        '(relation weighted 2)
        '(relation summary 2)
        '(rule (path ?x ?y) (edge ?x ?y))
        '(rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
        '(rule (allowed ?x ?y)
               (path ?x ?y) (not (blocked ?x ?y)))
        '(rule (weighted ?x ?v)
               (allowed ?x ?y) (weight ?y ?w)
               (where (even? ?w))
               (compute ?v (+ ?w ?w)))
        '(rule (summary ?r ?n)
               (root ?r)
               (reduce ?n (count) (weighted ?r ?v)))
        query
        '(limits 16 64 128)))

(def (check-case snapshot datum expected)
  (let* ((receipt (reasoning-attempt snapshot datum))
         (spec (candidate-inspect snapshot datum))
         (digest (reasoning-receipt-candidate-digest receipt))
         (rows (reasoning-receipt-rows receipt))
         (certificate
          (candidate-finite-evidence
           snapshot spec digest (reasoning-receipt-status receipt)
           rows 5000)))
    (check-equal? (reasoning-receipt-status receipt) 'complete)
    (check-equal? rows expected)
    (check-equal? (finite-evidence-status certificate) 'complete)
    (check-equal?
     (candidate-verify-finite-evidence
      snapshot spec digest 'complete rows certificate 5000)
     'valid)
    (values spec digest rows certificate)))

(def (reducer-program mode root)
  (list 'candidate
        '(relation total 2)
        (list 'rule '(total ?r ?v) '(root ?r)
              (list 'reduce '?v
                    (if (eq? mode 'count) '(count) (list mode '?w))
                    '(weight ?r ?w)))
        (list 'query 'total root '?v)
        '(limits 8 16 32)))

(def six-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))

(def (graph-edges mask)
  (filter-map
   (lambda (edge bit)
     (and (= (modulo (quotient mask (expt 2 bit)) 2) 1) edge))
   six-edges (iota 6)))

(def (finite-reachable edges)
  (let loop ((seen []) (pending (map cadr
                                    (filter (lambda (edge) (= (car edge) 0))
                                            edges))))
    (if (null? pending)
      seen
      (let (node (car pending))
        (if (member node seen)
          (loop seen (cdr pending))
          (loop (cons node seen)
                (append (cdr pending)
                        (map cadr
                             (filter (lambda (edge) (= (car edge) node))
                                     edges)))))))))

(def graph-program
  '(candidate
     (relation path 2)
     (relation allowed 2)
     (relation summary 2)
     (rule (path ?x ?y) (edge ?x ?y))
     (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
     (rule (allowed ?x ?y) (path ?x ?y)
           (not (blocked ?x ?y)))
     (rule (summary ?r ?n) (root ?r)
           (reduce ?n (count) (allowed ?r ?y)))
     (query summary 0 ?n)
     (limits 8 32 64)))

(def ascent-finite-evidence-test
  (test-suite "finite stratified replay evidence"
    (test-case "finite replay enforces exact schema and source row arity boundaries"
      (def (check-material input expected)
        (let* ((spec (make-reasoning-candidate '((target . 1)) [] [] (vector '(target 0) 0) '(1 1 1)))
               (certificate (candidate-finite-evidence input spec 'digest 'complete [] 100)))
          (check-equal? (finite-evidence-status certificate) expected)
          (if (eq? expected 'complete)
            (check-equal? (candidate-verify-finite-evidence input spec 'digest 'complete [] certificate 100) 'valid)
            (check-equal? (finite-evidence-closure certificate) []))))
      (for-each (lambda (count)
        (check-material (reasoning-source-snapshot 'schema-material 0
          (map (lambda (i) (list (string->symbol (string-append "seed" (number->string i))) 1 [])) (iota count)))
          (if (= count 63) 'complete 'bounded))) '(63 64))
      (for-each (lambda (width)
        (check-material (reasoning-source-snapshot 'arity-material 0
          (list (list 'seed width (list (make-list width 0)))))
          (if (= width 1024) 'complete 'bounded))) '(1024 1025)))
    (test-case "finite replay reserves seeds and derived rows within certificate material limits"
      (for-each (lambda (control)
        (let* ((width (car control)) (copies (cadr control))
               (names (map (lambda (i) (string->symbol (string-append "copy" (number->string i)))) (iota copies)))
               (terms (map (lambda (i) (string->symbol (string-append "?v" (number->string i)))) (iota width)))
               (input (reasoning-source-snapshot 'finite-material 0
                        (list (list 'seed width (map (lambda (i) (cons i (make-list (- width 1) 0))) (iota 1024))))))
               (spec (make-reasoning-candidate
                       (map (lambda (name) (cons name width)) names) []
                       (map (lambda (name i) (vector (cons name terms) (list (cons 'seed terms)) i)) names (iota copies))
                       (vector (cons (car names) (make-list width -1)) 99) '(1024 4096 4096)))
               (certificate (candidate-finite-evidence input spec 'digest 'complete [] 20000)))
          (check-equal? (finite-evidence-status certificate) (caddr control))
          (if (eq? (caddr control) 'complete)
            (begin
              (check-equal? (apply + (map (lambda (entry) (length (caddr entry))) (finite-evidence-closure certificate))) 4096)
              (check-equal? (candidate-verify-finite-evidence input spec 'digest 'complete [] certificate 20000) 'valid))
            (check-equal? (finite-evidence-closure certificate) []))
          (displayln "FINITE-MATERIAL-VERIFIED " width " " copies) (force-output)))
        '((1 3 complete) (1 4 bounded) (8 3 complete) (9 3 bounded))))
    (test-case "negation and count have an exact snapshot-relative closure"
      (let* ((snapshot (source 1 '((1 3))))
             (datum (program '(query summary 1 1))))
        (let-values (((spec digest rows certificate)
                      (check-case snapshot datum '((1 1)))))
          (check-equal?
           (candidate-verify-finite-evidence
            snapshot spec digest 'complete rows certificate 1)
           'bounded)
          (check-equal?
           (candidate-verify-finite-evidence
            (source 2 '((1 3))) spec digest 'complete rows certificate
            5000)
           'invalid)
          (let (closure (finite-evidence-closure certificate))
            (set-car! (cddr (assq 'allowed closure)) '((1 3)))
            (check-equal?
             (candidate-verify-finite-evidence
              snapshot spec digest 'complete rows certificate 5000)
             'invalid)))))
    (test-case "closed absence after negative and aggregate strata"
      (let ((snapshot (source 1 '((1 3)))))
        (check-case snapshot (program '(query summary 1 2)) '())))
    (test-case "source correction changes count but not old evidence"
      (let ((first (source 1 '((1 3))))
            (second (source 2 '())))
        (check-case first (program '(query summary 1 ?n)) '((1 1)))
        (check-case second (program '(query summary 1 ?n)) '((1 2)))))
    (test-case "replay mismatch is not certified"
      (let* ((snapshot (source 1 '((1 3))))
             (datum (program '(query summary 1 ?n)))
             (spec (candidate-inspect snapshot datum))
             (certificate
              (candidate-finite-evidence
               snapshot spec 'digest 'complete '((1 99)) 5000)))
        (check-equal? (finite-evidence-status certificate) 'mismatch)))
    (test-case "oversized external closure is rejected before replay"
      (let* ((snapshot (source 1 '((1 3))))
             (datum (program '(query summary 1 1)))
             (receipt (reasoning-attempt snapshot datum))
             (spec (candidate-inspect snapshot datum))
             (digest (reasoning-receipt-candidate-digest receipt))
             (rows (reasoning-receipt-rows receipt))
             (certificate
              (candidate-finite-evidence
               snapshot spec digest 'complete rows 5000)))
        (set-car! (cddr (assq 'allowed
                              (finite-evidence-closure certificate)))
                  (make-list 4097 '(1 2)))
        (check-equal?
         (candidate-verify-finite-evidence
          snapshot spec digest 'complete rows certificate 5000)
         'invalid)))
    (test-case "strict dependency cycle has no finite certificate"
      (let* ((snapshot
              (reasoning-source-snapshot
               'cycle 1 '((edge 2 ((1 2))))))
             (datum
              '(candidate
                 (relation a 1) (relation b 1)
                 (rule (a ?x) (edge ?x ?y) (not (b ?x)))
                 (rule (b ?x) (a ?x))
                 (query a ?x) (limits 8 16 32)))
             (spec (candidate-inspect snapshot datum))
             (certificate
              (candidate-finite-evidence
               snapshot spec 'digest 'complete [] 5000)))
        (check-equal? (finite-evidence-status certificate) 'unsupported)))
    (test-case "all fixed reducers and empty groups"
      (let (snapshot
            (reasoning-source-snapshot
             'reducers 1
             '((root 1 ((1) (2)))
               (weight 2 ((1 4) (1 6))))))
        (for-each
         (lambda (mode value empty)
           (check-case snapshot (reducer-program mode 1)
                       (list (list 1 value)))
           (check-case snapshot (reducer-program mode 2) empty))
         '(count sum min max)
         '(2 10 4 6)
         '(((2 0)) ((2 0)) () ()))))
    (test-case "negated wildcard checks absence of any matching row"
      (let ((snapshot
             (reasoning-source-snapshot
              'wildcard 1
              '((root 1 ((1) (2)))
                (weight 2 ((1 4) (1 6))))))
            (datum
             '(candidate
                (relation unmatched 1)
                (rule (unmatched ?r) (root ?r)
                      (not (weight ?r ?_)))
                (query unmatched ?r)
                (limits 8 16 32))))
        (check-case snapshot datum '((2)))))
    (test-case "all 64 three-node graphs match a separate reachability model"
      (for-each
       (lambda (mask)
         (let* ((edges (graph-edges mask))
                (snapshot
                 (reasoning-source-snapshot
                  'graphs mask
                  (list (list 'edge 2 edges)
                        '(blocked 2 ((0 2)))
                        '(root 1 ((0))))))
                (reachable (finite-reachable edges))
                (expected
                 (list
                  (list 0
                        (length
                         (filter (lambda (node) (not (= node 2)))
                                 reachable))))))
           (check-case snapshot graph-program expected)
           (when (zero? (modulo (+ mask 1) 2))
             (displayln "PROGRESS finite evidence graphs " (+ mask 1) "/64")
             (force-output))))
       (iota 64)))))
