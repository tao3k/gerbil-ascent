;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-suite test-case)
        :gerbil-ascent/candidate/feedback
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot
                 reasoning-attempt reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-proof reasoning-receipt-nonmembership
                 reasoning-receipt-diagnostics reasoning-diagnostic-code))
(export ascent-candidate-feedback-test ascent-scoped-attempt-feedback-test)
(def (append-map f rows) (apply append (map f rows)))
(def edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def (graph mask)
  (filter-map (lambda (bit) (and (not (zero? (bitwise-and mask (arithmetic-shift 1 bit)))) (list-ref edges bit)))
              (iota 6)))
;;; Independent positive-length graph walk, including cycles back to origin.
(def (oracle pairs)
  (append-map
   (lambda (origin)
     (let loop ((pending (map cadr (filter (lambda (e) (= (car e) origin)) pairs))) (seen []))
       (if (null? pending) (map (lambda (target) (list origin target)) seen)
           (let (v (car pending))
             (if (member v seen) (loop (cdr pending) seen)
                 (loop (append (cdr pending) (map cadr (filter (lambda (e) (= (car e) v)) pairs)))
                       (cons v seen))))))) '(0 1 2)))
(def (proposal variant)
  (append '(candidate (relation path 2))
          (cond ((eq? variant 'no-base) [])
                ((eq? variant 'reverse-base) '((rule (path ?x ?y) (edge ?y ?x))))
                (else '((rule (path ?x ?y) (edge ?x ?y)))))
          (if (eq? variant 'no-step) []
              (list (list 'rule '(path ?x ?z) '(path ?x ?y)
                          (if (eq? variant 'wrong-join) '(edge ?x ?z) '(edge ?y ?z)))))
          '((query path ?x ?y) (limits 16 64 128))))
(def (snapshot generation pairs)
  (reasoning-source-snapshot 'db26-graph generation (list (list 'edge 2 pairs))))
(def (compare source p wanted)
  (reasoning-compare-rows source p (reasoning-attempt source p #f) wanted))
(def ascent-candidate-feedback-test
  (test-suite "DB26 candidate execution feedback"
    (test-case "frozen proposals on 64 held-out graphs with exact differences"
      (let (kills (make-hash-table-eq))
        (for-each
         (lambda (mask)
           (let* ((pairs (graph mask)) (source (snapshot mask pairs)) (wanted (oracle pairs)))
             (for-each
              (lambda (variant)
                (let* ((p (proposal variant)) (receipt (reasoning-attempt source p #f))
                       (actual (reasoning-receipt-rows receipt))
                       (feedback (reasoning-compare-rows source p receipt wanted))
                       (missing (filter (lambda (r) (not (member r actual))) wanted))
                       (extra (filter (lambda (r) (not (member r wanted))) actual)))
                  (check-equal? (reasoning-receipt-status receipt) 'complete)
                  (check-equal? (reasoning-receipt-proof receipt) #f)
                  (check-equal? (reasoning-receipt-nonmembership receipt) #f)
                  (check-equal? (reasoning-feedback-status feedback)
                                (if (and (null? missing) (null? extra)) 'match 'mismatch))
                  (check-equal? (reasoning-feedback-missing feedback) missing)
                  (check-equal? (reasoning-feedback-extra feedback) extra)
                  (when (eq? variant 'correct) (check-equal? (reasoning-feedback-status feedback) 'match))
                  (when (eq? (reasoning-feedback-status feedback) 'mismatch) (hash-put! kills variant #t))))
              '(correct no-base no-step wrong-join reverse-base)))
           (when (zero? (modulo (+ mask 1) 8))
             (displayln "DB26-GRAPHS " (+ mask 1) "/64") (force-output))) (iota 64))
        (for-each (lambda (v) (check-equal? (hash-get kills v) #t)) '(no-base no-step wrong-join reverse-base))))
    (test-case "a demonstration pass fails on the held-out chain"
      (let (p (proposal 'wrong-join))
        (check-equal? (reasoning-feedback-status (compare (snapshot 0 '((0 1))) p '((0 1)))) 'match)
        (let (f (compare (snapshot 1 '((0 1) (1 2))) p '((0 1) (1 2) (0 2))))
          (check-equal? (reasoning-feedback-status f) 'mismatch)
          (check-equal? (reasoning-feedback-missing f) '((0 2))))))
    (test-case "withdrawal, candidate binding, rejected and unfinished attempts"
      (let* ((p (proposal 'correct)) (source (snapshot 0 '((0 1) (1 2))))
             (receipt (reasoning-attempt source p 1)) (changed (snapshot 1 '((0 1))))
             (bad '(candidate (relation path 2) (rule (path ?x ?y) (helper ?x ?y))
                              (query path ?x ?y) (limits 16 64 128)))
             (rejected (reasoning-attempt source bad))
             (limited (append (reverse (cdr (reverse p))) '((limits 16 1 1)))))
        (check-equal? (reasoning-feedback-reason (reasoning-compare-rows changed p receipt '((0 1)))) 'unbound)
        (check-equal? (reasoning-feedback-reason (reasoning-compare-rows source (proposal 'wrong-join) receipt [])) 'unbound)
        (check-equal? (reasoning-feedback-status (compare changed p '((0 1)))) 'match)
        (check-equal? (reasoning-diagnostic-code (car (reasoning-receipt-diagnostics rejected))) 'unknown-relation)
        (check-equal? (reasoning-feedback-reason (reasoning-compare-rows source bad rejected [])) 'rejected)
        (check-equal? (reasoning-feedback-status (compare source limited [])) 'inconclusive)))
    (test-case "set semantics and bounded reference validation"
      (let* ((p (proposal 'correct)) (source (snapshot 0 '((0 1)))) (r (reasoning-attempt source p 1)))
        (check-equal? (reasoning-feedback-status (reasoning-compare-rows source p r '((0 1) (0 1)))) 'match)
        (let* ((row (list 0 2)) (wanted (list row))
               (f (reasoning-compare-rows source p r wanted)))
          (set-car! row 9)
          (check-equal? (reasoning-feedback-missing f) '((0 2)))
          (check-equal? (reasoning-feedback-extra f) '((0 1))))
        (for-each (lambda (bad) (check-equal? (reasoning-feedback-reason (reasoning-compare-rows source p r bad)) 'invalid-reference))
                  (list '((0)) '((0 1) . 2) (list (list 0 (lambda () 1))) (make-list 6000 '(0 1))))
        (let (cycle (list '(0 1)))
          (set-cdr! cycle cycle)
          (check-equal? (reasoning-feedback-reason (reasoning-compare-rows source p r cycle)) 'invalid-reference))))))

;;; Frozen specification controls, not model-generated proposals. The excluded
;;; city 0 survives through direct; city 2 has only the excluded route witness.
(def (scoped-proposal variant (query '(query answer ?city)))
  (append '(candidate (relation answer 1) (relation joined 1)
             (rule (joined ?city) (route ?city))
             (rule (joined ?city) (direct ?city)))
          (case variant
            ((gold) '((rule (answer ?city) (route ?city) (not (capital ?city)))
                      (rule (answer ?city) (direct ?city))))
            ((global) '((rule (answer ?city) (joined ?city) (not (capital ?city)))))
            (else '((rule (answer ?city) (joined ?city)))))
          (list query '(limits 16 64 128))))
(def (scoped-source generation)
  (reasoning-source-snapshot 'ml26-scope-control generation
    '((route 1 ((0) (1) (2))) (direct 1 ((0))) (capital 1 ((0) (2))))))
(def ascent-scoped-attempt-feedback-test
  (test-suite "ML26 same-source proposal comparison"
    (test-case "complete scope errors have exact missing and extra rows"
      (let* ((source (scoped-source 0)) (gold (scoped-proposal 'gold))
             (reference (reasoning-attempt source gold #f))
             (global (scoped-proposal 'global)) (positive (scoped-proposal 'positive))
             (global-receipt (reasoning-attempt source global #f))
             (positive-receipt (reasoning-attempt source positive #f))
             (missing (reasoning-compare-attempts source global global-receipt gold reference))
             (extra (reasoning-compare-attempts source positive positive-receipt gold reference)))
        (for-each (lambda (r) (check-equal? (reasoning-receipt-status r) 'complete))
                  (list reference global-receipt positive-receipt))
        (check-equal? (reasoning-feedback-status missing) 'mismatch)
        (check-equal? (reasoning-feedback-missing missing) '((0)))
        (check-equal? (reasoning-feedback-extra missing) [])
        (check-equal? (reasoning-feedback-status extra) 'mismatch)
        (check-equal? (reasoning-feedback-missing extra) [])
        (check-equal? (reasoning-feedback-extra extra) '((2)))
        (check-equal? (reasoning-feedback-status
                       (reasoning-compare-attempts source gold reference gold reference)) 'match)
        ;; Caller-selected gold can itself have the wrong scope. A match is
        ;; an executor comparison, not a theorem about natural-language intent.
        (check-equal? (reasoning-feedback-status
                       (reasoning-compare-attempts source global global-receipt global global-receipt)) 'match)))
    (test-case "both receipt bindings and reference completion gate comparison"
      (let* ((source (scoped-source 0)) (new-source (scoped-source 1))
             (gold (scoped-proposal 'gold)) (p (scoped-proposal 'global))
             (reference (reasoning-attempt source gold #f))
             (current (reasoning-attempt new-source p #f))
             (rejected-p '(candidate (relation answer 1)
                            (rule (answer ?city) (unknown ?city))
                            (query answer ?city) (limits 16 64 128)))
             (rejected (reasoning-attempt new-source rejected-p #f)))
        (check-equal? (reasoning-feedback-reason
                       (reasoning-compare-attempts new-source p current gold reference)) 'reference-unbound)
        (check-equal? (reasoning-feedback-reason
                       (reasoning-compare-attempts source p current gold reference)) 'unbound)
        (check-equal? (reasoning-feedback-reason
                       (reasoning-compare-attempts source gold reference p reference)) 'reference-unbound)
        (let (f (reasoning-compare-attempts new-source p current rejected-p rejected))
          (check-equal? (reasoning-feedback-reason f) 'reference-incomplete)
          (check-equal? (reasoning-feedback-missing f) [])
          (check-equal? (reasoning-feedback-extra f) []))
        (check-equal? (reasoning-feedback-reason
                       (reasoning-compare-attempts new-source rejected-p rejected p current)) 'rejected)
        (let* ((limited (append (reverse (cdr (reverse gold))) '((limits 16 1 1))))
               (unfinished (reasoning-attempt new-source limited #f)))
          (check-equal? (eq? (reasoning-receipt-status unfinished) 'complete) #f)
          (check-equal? (reasoning-feedback-reason
                         (reasoning-compare-attempts new-source p current limited unfinished)) 'reference-incomplete))))
    (test-case "equal arity with a changed query constant is not comparable"
      (let* ((source (scoped-source 0)) (gold (scoped-proposal 'gold))
             (p (scoped-proposal 'gold '(query answer 0)))
             (reference (reasoning-attempt source gold #f))
             (r (reasoning-attempt source p #f)))
        (check-equal? (reasoning-receipt-status r) 'complete)
        (check-equal? (reasoning-feedback-reason
                       (reasoning-compare-attempts source p r gold reference)) 'query-mismatch)))
    (test-case "published differences do not retain reference row pairs"
      (let* ((source (scoped-source 0)) (gold (scoped-proposal 'gold))
             (p (scoped-proposal 'global)) (reference (reasoning-attempt source gold #f))
             (r (reasoning-attempt source p #f))
             (f (reasoning-compare-attempts source p r gold reference)))
        (set-car! (car (reasoning-feedback-missing f)) 9)
        (check-equal? (reasoning-feedback-missing
                       (reasoning-compare-attempts source p r gold reference)) '((0)))))))
