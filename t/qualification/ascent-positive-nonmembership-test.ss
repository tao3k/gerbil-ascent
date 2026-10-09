;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/provenance
                 candidate-positive-closed-absence positive-proof-status positive-proof-nodes
                 candidate-positive-proof)
        (only-in :gerbil-ascent/candidate/types
                 make-reasoning-snapshot make-reasoning-candidate
                 reasoning-snapshot-digest reasoning-snapshot-relations reasoning-candidate-query)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-candidate-digest
                 reasoning-receipt-nonmembership)
        (only-in :gerbil-ascent/candidate/nonmembership
                 candidate-positive-nonmembership
                 candidate-verify-positive-nonmembership
                 positive-nonmembership-status
                 positive-nonmembership-closure))

(export ascent-positive-nonmembership-test)

(def (snapshot)
  (reasoning-source-snapshot
   'graph 9 '((edge 2 ((1 2) (2 4))))))

(def (spec query (facts []))
  (make-reasoning-candidate
   '((path . 2)) facts
   (list
    (vector '(path ?x ?y) '((edge ?x ?y)) 3)
    (vector '(path ?x ?z)
            '((path ?x ?y) (edge ?y ?z)) 4))
   (vector query 5)
   '(12 32 32)))

(def (verify cert snapshot spec (native-rows []) (budget 500))
  (candidate-verify-positive-nonmembership
   snapshot spec 'candidate-digest 'complete native-rows cert budget))

(def ascent-positive-nonmembership-test
  (test-suite "finite positive ground nonmembership"
    (test-case "absence material limits include seeds and pending rows before publication"
      (def (fixture width copies)
        (let* ((names (map (lambda (i) (string->symbol (string-append "copy" (number->string i)))) (iota copies)))
               (terms (map (lambda (i) (string->symbol (string-append "?v" (number->string i)))) (iota width)))
               (input (reasoning-source-snapshot 'material 0
                         (list (list 'seed width
                           (map (lambda (i) (cons i (make-list (- width 1) 0))) (iota 1024))))))
               (program (make-reasoning-candidate
                          (map (lambda (name) (cons name width)) names)
                          (list (vector 'seed (make-list width 0) 100))
                          (cons (vector (cons (car names) terms) (list (cons 'seed terms)) 101)
                            (map (lambda (name label) (vector (cons name terms) (list (cons 'seed terms)) label)) names (iota copies)))
                          (vector (cons (car names) (make-list width -1)) 99) '(1024 4096 4096))))
          (values input program)))
      (for-each (lambda (control)
        (let-values (((input program) (fixture (car control) (cadr control))))
          ;; Duplicate clauses require up to 10240 probes for a full replay;
          ;; this budget isolates material exhaustion from work exhaustion.
          (let ((proof (candidate-positive-closed-absence input program 'digest 'complete [] 20000))
                (certificate (candidate-positive-nonmembership input program 'digest 'complete [] 20000)))
            (check-equal? (positive-proof-status proof) (caddr control))
            (check-equal? (positive-nonmembership-status certificate) (cadddr control))
            (if (eq? (caddr control) 'bounded)
              (begin (check-equal? (positive-proof-nodes proof) [])
                     (check-equal? (positive-nonmembership-closure certificate) []))
              (begin (check-equal? (length (positive-proof-nodes proof)) 4096)
                     (check-equal? (candidate-verify-positive-nonmembership input program 'digest 'complete [] certificate 20000) 'valid)))
            (when (and (= (car control) 1) (= (cadr control) 4))
              ;; The absence material cap must not replace a positive witness's
              ;; admitted derived-fact budget (1024 seeds plus 4096 derived).
              (vector-set! (reasoning-candidate-query program) 0 '(copy0 0))
              (let (positive (candidate-positive-proof input program 'digest 'complete '((0)) 20000))
                (check-equal? (positive-proof-status positive) 'complete)
                (check-equal? (length (positive-proof-nodes positive)) 5120))))))
        '((1 3 closed-absent complete) (1 4 bounded bounded)
          (8 3 closed-absent complete) (9 3 bounded bounded))))
    (test-case "combined source and candidate schema exceeds absence certificate capacity"
      (let* ((input (reasoning-source-snapshot 'schema-capacity 0
                       (map (lambda (i) (list (string->symbol (string-append "source" (number->string i))) 1 [])) (iota 64))))
             (program (make-reasoning-candidate '((target . 1)) [] [] (vector '(target 0) 0) '(1 1 1)))
             (certificate (candidate-positive-nonmembership input program 'digest 'complete [] 100)))
        (check-equal? (positive-nonmembership-status certificate) 'bounded)
        (check-equal? (positive-nonmembership-closure certificate) [])))
    (test-case "wide source row reserves material at the exact arity boundary"
      (for-each (lambda (width)
        (let* ((input (reasoning-source-snapshot 'wide-source 0
                        (list (list 'seed width (list (make-list width 0))))))
               (program (make-reasoning-candidate '((target . 1)) [] [] (vector '(target 0) 0) '(1 1 1)))
               (proof (candidate-positive-closed-absence input program 'digest 'complete [] 100))
               (certificate (candidate-positive-nonmembership input program 'digest 'complete [] 100)))
          (if (= width 1024)
            (begin (check-equal? (positive-proof-status proof) 'closed-absent)
                   (check-equal? (length (positive-proof-nodes proof)) 1)
                   (check-equal? (positive-nonmembership-status certificate) 'complete)
                   (check-equal? (candidate-verify-positive-nonmembership input program 'digest 'complete [] certificate 100) 'valid))
            (begin (check-equal? (positive-proof-status proof) 'bounded)
                   (check-equal? (positive-proof-nodes proof) [])
                   (check-equal? (positive-nonmembership-status certificate) 'bounded)
                   (check-equal? (positive-nonmembership-closure certificate) [])))))
        '(1024 1025)))
    (test-case "public receipt carries independently verifiable absence"
      (let* ((input
              (reasoning-source-snapshot
               'graph 9 '((edge 2 ((1 2) (2 4))))))
             (datum
              '(candidate
                 (relation path 2)
                 (rule (path ?x ?y) (edge ?x ?y))
                 (rule (path ?x ?z)
                       (path ?x ?y) (edge ?y ?z))
                 (query path 1 3)
                 (limits 12 32 32)))
             (receipt (reasoning-attempt input datum))
             (cert (reasoning-receipt-nonmembership receipt))
             (checked (candidate-inspect input datum)))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-receipt-rows receipt) '())
        (check-equal? (positive-nonmembership-status cert) 'complete)
        (check-equal?
         (candidate-verify-positive-nonmembership
          input checked (reasoning-receipt-candidate-digest receipt)
          (reasoning-receipt-status receipt)
          (reasoning-receipt-rows receipt) cert 500)
         'valid)))
    (test-case "closed relation set certifies missing ground target"
      (let* ((input (snapshot))
             (program (spec '(path 1 3)))
             (cert
              (candidate-positive-nonmembership
               input program 'candidate-digest 'complete [] 500)))
        (check-equal? (positive-nonmembership-status cert) 'complete)
        (check-equal? (positive-nonmembership-closure cert)
                      '((edge 2 ((1 2) (2 4)))
                        (path 2 ((1 2) (2 4) (1 4)))))
        (check-equal? (verify cert input program) 'valid)
        (check-equal? (verify cert input program [] 1) 'bounded)
        (check-equal? (verify cert input program [] 7) 'bounded)
        (check-equal?
         (candidate-verify-positive-nonmembership
          input program 'other-digest 'complete [] cert 500)
         'invalid)))
    (test-case "mutable or forged snapshot content invalidates certificate"
      (let* ((input (snapshot))
             (program (spec '(path 1 3)))
             (cert
              (candidate-positive-nonmembership
               input program 'candidate-digest 'complete [] 500))
             (forged
              (make-reasoning-snapshot
               'graph 9 (reasoning-snapshot-digest input)
               '((edge 2 ((1 7) (2 4)))))))
        (check-equal? (verify cert forged program) 'invalid)
        (check-equal?
         (positive-nonmembership-status
          (candidate-positive-nonmembership
           forged program 'candidate-digest 'complete [] 500))
         'unsupported)
        (set-car! (car (caddar (reasoning-snapshot-relations input))) 99)
        (check-equal? (verify cert input program) 'invalid)
        (check-equal?
         (positive-nonmembership-status
          (candidate-positive-nonmembership
           input program 'candidate-digest 'complete [] 500))
         'unsupported)))
    (test-case "checker rejects omitted input and broken rule closure"
      (let* ((input (snapshot))
             (program (spec '(path 1 3)))
             (cert
              (candidate-positive-nonmembership
               input program 'candidate-digest 'complete [] 500))
             (closure (positive-nonmembership-closure cert)))
        (set-car! (cddr (car closure)) '((1 2)))
        (check-equal? (verify cert input program) 'invalid)
        (let* ((second
                (candidate-positive-nonmembership
                 input program 'candidate-digest 'complete [] 500))
               (rows (caddr (cadr
                              (positive-nonmembership-closure second)))))
          (set-cdr! rows '())
          (check-equal? (verify second input program) 'invalid))))
    (test-case "oversized external certificates fail before rule traversal"
      (let* ((input (snapshot))
             (program (spec '(path 1 3)))
             (too-many-rows
              (candidate-positive-nonmembership
               input program 'candidate-digest 'complete [] 500))
             (first-relation
              (car (positive-nonmembership-closure too-many-rows))))
        (set-car! (cddr first-relation)
                  (make-list 4097 '(1 2)))
        (check-equal? (verify too-many-rows input program) 'invalid)
        (let* ((too-many-relations
                (candidate-positive-nonmembership
                 input program 'candidate-digest 'complete [] 500))
               (relations
                (positive-nonmembership-closure too-many-relations)))
          (set-cdr! (cdr relations)
                    (make-list 65 '(extra 0 ())))
          (check-equal? (verify too-many-relations input program)
                        'invalid))))
    (test-case "candidate fact is required in closure"
      (let* ((input (snapshot))
             (program
              (spec '(path 1 3) (list (vector 'edge '(2 3) 6))))
             (cert
              (candidate-positive-nonmembership
               input program 'candidate-digest 'complete [] 500)))
        (check-equal? (positive-nonmembership-status cert) 'unsupported)
        (let* ((missing
                (spec '(path 1 5)
                      (list (vector 'edge '(2 3) 6))))
               (valid
                (candidate-positive-nonmembership
                 input missing 'candidate-digest 'complete [] 500))
               (edge-rows
                (caddr (car (positive-nonmembership-closure valid)))))
          (check-equal? (positive-nonmembership-status valid) 'complete)
          (check-equal? (verify valid input missing) 'valid)
          (set-cdr! (cdr edge-rows) '())
          (check-equal? (verify valid input missing) 'invalid))))
    (test-case "fixed arithmetic is replayed in an absence certificate"
      (let* ((input
              (reasoning-source-snapshot
               'arithmetic 1 '((edge 2 ((1 2) (1 3) (2 4))))))
             (datum
              '(candidate
                 (relation doubled 2)
                 (rule (doubled ?x ?z)
                   (edge ?x ?y) (where (even? ?y))
                   (compute ?z (+ ?y ?y)) (where (< ?x ?z)))
                 (query doubled 1 8) (limits 8 16 32)))
             (receipt (reasoning-attempt input datum))
             (program (candidate-inspect input datum))
             (cert (reasoning-receipt-nonmembership receipt)))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-receipt-rows receipt) '())
        (check-equal? (positive-nonmembership-status cert) 'complete)
        (check-equal?
         (candidate-verify-positive-nonmembership
          input program (reasoning-receipt-candidate-digest receipt)
          'complete [] cert 500)
         'valid)
        (set-car! (cddr (cadr (positive-nonmembership-closure cert)))
                  '((1 6) (2 8)))
        (check-equal?
         (candidate-verify-positive-nonmembership
          input program (reasoning-receipt-candidate-digest receipt)
          'complete [] cert 500)
         'invalid)))
    (test-case "non-ground, nonpositive and incomplete executions abstain"
      (let* ((input (snapshot))
             (ground (spec '(path 1 3)))
             (non-ground (spec '(path 1 ?z)))
             (negative
              (make-reasoning-candidate
               '((allowed . 2)) []
               (list (vector '(allowed ?x ?y)
                             '((edge ?x ?y)
                               (not (blocked ?x ?y))) 3))
               (vector '(allowed 1 3) 4) '(12 32 32))))
        (check-equal?
         (positive-nonmembership-status
          (candidate-positive-nonmembership
           input non-ground 'candidate-digest 'complete [] 500))
         'unsupported)
        (check-equal?
         (positive-nonmembership-status
          (candidate-positive-nonmembership
           input negative 'candidate-digest 'complete [] 500))
         'unsupported)
        (check-equal?
         (positive-nonmembership-status
          (candidate-positive-nonmembership
           input ground 'candidate-digest 'unknown [] 500))
         'unsupported)
        (check-equal?
         (positive-nonmembership-status
          (candidate-positive-nonmembership
           input ground 'candidate-digest 'complete [] 1))
         'bounded)))))
