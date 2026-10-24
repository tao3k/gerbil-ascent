;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-fragment relational-export
                 relational-compose relational-admit relational-admit/report
                 relational-admission-report-diagnostic relational-diagnostic-code
                 relational-solve relational-query-name))
(import (only-in :clan/poo/object .o .ref .putslot! uninstantiate-object! object-instance $constant-slot-spec $thunk-slot-spec)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program gerbil-ascent-rule
                 gerbil-ascent-atom gerbil-ascent-variable gerbil-ascent-literal)
        (only-in :gerbil-ascent/program/scheme-checked relational-source)
        (only-in :gerbil-ascent/program/scheme-snapshot relational-snapshot-program)
        (only-in :gerbil-ascent/program/types GerbilAscentTermContract)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (prefix-in :gerbil-ascent/t/qualification/scheme-snapshot-reference frozen-)
        (only-in :gerbil-ascent/t/performance/operator-publication/fixture publication-shape)
        (only-in :gerbil-ascent/t/qualification/fixtures/semi-naive/oracle
                 graph-input naive-positive naive-rules canonical-rows))
(export scheme-closure-contract-test)

(def (successor-program bounded?)
  (if bounded?
    (relational-program
     (relation number (value) '((0)))
     (rule (number ?next) (number ?n)
       (where (< ?n 4)) (compute ?next (+ ?n 1)))
     (limits 8 8 16))
    (relational-program
     (relation number (value) '((0)))
     (rule (number ?next) (number ?n) (compute ?next (+ ?n 1)))
     (limits 8 8 16))))


(def (snapshot-checks-active?)
  (with-catch (lambda (_) #t)
    (lambda () (gerbil-ascent-rule '(99) []) #f)))

;;; A checked-domain getter is intentionally outside the ordinary Relation
;;; responsibilities. It must never observe the private construction extent.
(def (snapshot-callback-report copier mode)
  (let ((program #f) (events []) (term (gerbil-ascent-variable 'x)))
    (def (record! event) (set! events (cons event events)))
    (let* ((source
             (.o (:: @ (relational-source 'input 1 '((0))))
                 (checked-domain
                  (begin
                    (record! 'getter)
                    (record! (snapshot-checks-active?))
                    (case mode
                      ((term-failure)
                       (.putslot! term 'value ($constant-slot-spec 99))
                       (uninstantiate-object! term)
                       (.putslot! program 'max-output-facts
                         ($thunk-slot-spec (lambda () (record! 'late-budget) 8)))
                       (uninstantiate-object! program))
                      ((root-failure)
                       (.putslot! program 'max-input-facts ($constant-slot-spec -1))
                       (uninstantiate-object! program))
                      ((getter-failure) (error "snapshot getter failed")))
                    #f))))
           (answer (relational-source 'answer 1 [])))
      (set! program
        (gerbil-ascent-program (list source answer)
          (list (gerbil-ascent-rule
                  (list (gerbil-ascent-atom 'answer (list term)))
                  (list (gerbil-ascent-atom 'input (list term))))) 8 8 8))
      (let (outcome
            (with-catch error-message
              (lambda ()
                (let* ((copied (copier program))
                       (result (gerbil-ascent-evaluate-program copied)))
                  ((.ref result 'rows-of) 'answer)))))
        (list outcome (reverse events) (snapshot-checks-active?))))))

(def (snapshot-graph-program mask)
  (def (atom form)
    (gerbil-ascent-atom (car form) (map gerbil-ascent-variable (cdr form))))
  (gerbil-ascent-program
    (list (relational-source 'edge 2 (graph-input mask))
          (relational-source 'p 2 []) (relational-source 'q 2 []))
    (map (lambda (rule)
           (gerbil-ascent-rule (list (atom (car rule))) (map atom (cdr rule)))) naive-rules)
    10000 10000 10000))

(def scheme-closure-contract-test
  (test-suite "Scheme closure guarantees and operational failure boundaries"
    (test-case "captured snapshots retain the frozen AST and independent graph oracle in serial and twelve-worker requests"
      (for-each
        (lambda (mask)
          (let* ((program (snapshot-graph-program mask))
                 (before (frozen-relational-snapshot-program program))
                 (after (relational-snapshot-program program)))
            (check-equal? (publication-shape after 'p) (publication-shape before 'p))
            (for-each
              (lambda (slot) (check-equal? (.ref after slot) (.ref before slot)))
              '(max-input-facts max-derived-facts max-output-facts))
            (let-values (((expected _) (naive-positive (graph-input mask) naive-rules)))
              (for-each
                (lambda (workers)
                  (for-each
                    (lambda (snapshot)
                      (let (result (gerbil-ascent-evaluate-program snapshot workers: workers))
                        (check-equal? (.ref result 'finished) #t)
                        (for-each
                          (lambda (name)
                            (check-equal? (canonical-rows ((.ref result 'rows-of) name))
                                          (canonical-rows (cdr (assq name expected))))) '(edge p q))))
                    (list before after))) '(1 12)))))
        (iota 64)))
    (test-case "actual positive snapshot Term classifiers retain both complete roots and remove only intermediate checks"
      (let ((program (snapshot-graph-program 63))
            (classifier (.ref GerbilAscentTermContract '.classify)))
        (def (count-checks copier)
          (let (checks 0)
            (try
              ;; Keep the descriptor's nominal proto and responsibility map.
              ;; Invalidating the entire descriptor would construct a new proto.
              (hash-put! (object-instance GerbilAscentTermContract) '.classify
                (lambda (candidate context)
                  (set! checks (+ checks 1))
                  (classifier candidate context)))
              (copier program)
              checks
              (finally
                (hash-put! (object-instance GerbilAscentTermContract) '.classify classifier)))))
        (check-equal? (count-checks frozen-relational-snapshot-program) (* 5 14))
        (check-equal? (count-checks relational-snapshot-program) (* 2 14))
        (check-equal? (snapshot-checks-active?) #t)))
    (test-case "snapshot getters retain immediate public checks and failure ordering against the frozen copier"
      (check-equal? (snapshot-callback-report relational-snapshot-program 'success)
                    '(((0)) (getter #t) #t))
      (for-each
        (lambda (mode)
          (check-equal? (snapshot-callback-report relational-snapshot-program mode)
                        (snapshot-callback-report frozen-relational-snapshot-program mode)))
        '(success getter-failure term-failure root-failure)))
    (test-case "snapshot capture rejects a mutated Term before forcing later budget getters"
      (check-equal? (snapshot-callback-report relational-snapshot-program 'term-failure)
                    '("ASCENT variable name must be a symbol" (getter #t) #t)))
    (test-case "snapshot copies remain detached and later calls observe fresh mutable Terms"
      (let* ((term (gerbil-ascent-literal 0))
             (program (gerbil-ascent-program
                        (list (relational-source 'answer 1 []))
                        (list (gerbil-ascent-rule
                                (list (gerbil-ascent-atom 'answer (list term))) [])) 8 8 8))
             (first (relational-snapshot-program program)))
        (.putslot! term 'value ($constant-slot-spec 1))
        (uninstantiate-object! term)
        (let ((second (relational-snapshot-program program))
              (frozen (frozen-relational-snapshot-program program)))
          (check-equal? (publication-shape second 'answer) (publication-shape frozen 'answer))
          (check-equal? ((.ref (gerbil-ascent-evaluate-program first) 'rows-of) 'answer) '((0)))
          (check-equal? ((.ref (gerbil-ascent-evaluate-program second) 'rows-of) 'answer) '((1))))))
    (test-case "finite successor completes with the exact independent interval"
      (let (answer (relational-query-name
                    (relational-solve (relational-admit (successor-program #t)))
                    'number))
        (check-equal? (length answer) 5)
        (for-each (lambda (n) (check-equal? (if (member (list n) answer) #t #f) #t))
                  '(0 1 2 3 4))))
    (test-case "monotone integer successor does not become complete at a budget"
      (let (admission (relational-admit (successor-program #f)))
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "ASCENT derived fact budget exceeded")))
        ;; Failed admissions cannot subsequently publish a truncated closure.
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "relational solve previously failed")))))
    (test-case "one lattice key does not imply finite-height refinement"
      (let (admission
            (relational-admit
             (relational-program
              (lattice best (key value) '((0 0)) max)
              (rule (best ?key ?next) (best ?key ?n)
                (compute ?next (+ ?n 1)))
              (limits 8 8 16))))
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "ASCENT derived fact budget exceeded")))
        (check-exception (relational-solve admission)
          (lambda (failure)
            (equal? (error-message failure) "relational solve previously failed")))))
    (test-case "separately admissible fragments can compose into a negative cycle"
      (let* ((base
              (relational-fragment
               (import) (source (seed (value) '((1)))
                                (a (value) []) (b (value) []))
               (private) (export (seed seed) (a a) (b b))))
             (seed (relational-export base 'seed))
             (a (relational-export base 'a))
             (b (relational-export base 'b))
             (left
              (relational-fragment
               (import (seed seed) (a a) (b b)) (source) (private) (export)
               (rule (a ?x) (seed ?x) (not (b ?x)))))
             (right
              (relational-fragment
               (import (seed seed) (a a) (b b)) (source) (private) (export)
               (rule (b ?x) (seed ?x) (not (a ?x)))))
             (combined (relational-compose (list base left right) 8 8 16)))
        (relational-solve (relational-admit (relational-compose (list base left) 8 8 16)))
        (relational-solve (relational-admit (relational-compose (list base right) 8 8 16)))
        (check-equal?
         (relational-diagnostic-code
          (relational-admission-report-diagnostic (relational-admit/report combined)))
         'invalid-dependencies)
        (check-exception (relational-admit combined) true)))))
