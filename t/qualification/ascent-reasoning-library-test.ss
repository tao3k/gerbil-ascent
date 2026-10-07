;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :gerbil-ascent/candidate/types
                 make-reasoning-snapshot reasoning-snapshot-valid?)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-bound?
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt
                 reasoning-snapshot-digest
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-diagnostics reasoning-receipt-evidence
                 reasoning-receipt-stratified
                 reasoning-stratified-evidence-status
                 reasoning-stratified-evidence-finite
                 reasoning-stratified-evidence-proof
                 reasoning-receipt-snapshot-generation
                 reasoning-receipt-snapshot-digest
                 reasoning-diagnostic-code reasoning-diagnostic-path
                 reasoning-evidence-kind reasoning-evidence-support
                 reasoning-evidence-reachable)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 finite-evidence-closure)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-open-program-session
                 relational-program-session-run relational-program-query
                 relational-program-replace-source!))

(export ascent-reasoning-library-test)

(def (proposal origin target (extra []) (limits '(limits 16 32 64)))
  (append
   '(candidate
      (relation path 2)
      (rule (path ?x ?y) (edge ?x ?y))
      (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z)))
   extra
   (list (list 'query 'path origin target) limits)))

(def (first-diagnostic receipt)
  (car (reasoning-receipt-diagnostics receipt)))

(def (edge-snapshot generation rows)
  (reasoning-source-snapshot 'graph generation
                             (list (list 'edge 2 rows))))

;;; Reference closure enumerates vertex triples, without using rule engine.
(def (reference-closure edges)
  (let (matrix (make-vector 9 #f))
    (for-each
     (lambda (edge)
       (vector-set! matrix (+ (* 3 (car edge)) (cadr edge)) #t))
     edges)
    (for-each
     (lambda (pivot)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (+ (* 3 from) pivot))
                        (vector-ref matrix (+ (* 3 pivot) to)))
               (vector-set! matrix (+ (* 3 from) to) #t)))
           '(0 1 2)))
        '(0 1 2)))
     '(0 1 2))
    (let (rows [])
      (for-each
       (lambda (from)
         (for-each
          (lambda (to)
            (when (vector-ref matrix (+ (* 3 from) to))
              (set! rows (cons (list from to) rows))))
          '(0 1 2)))
       '(0 1 2))
      (reverse rows))))

(def (same-rows? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)))

;;; A scripted caller can revise a proposal without changing the Library's
;;; source snapshot. The finite reference calculates the intended summary
;;; from graph closure and scalar weights, independently of rule evaluation.
(def (rich-proposal join (extra []))
  (append
   ;; This declaration is mutated by the receipt-isolation Case.
   ;; Allocate the pair at runtime; compiled quoted data is immutable.
   (list 'candidate
         (list 'relation 'path 2)
         '(relation allowed 2)
         '(relation score 2)
         '(relation summary 2)
         '(rule (path ?x ?y) (edge ?x ?y)))
   (list (list 'rule '(path ?x ?z)
               '(path ?x ?y) (list 'edge join '?z)))
   '((rule (allowed ?x ?y)
       (path ?x ?y) (not (blocked ?x ?y)))
     (rule (score ?x ?d)
       (allowed ?x ?y) (weight ?y ?w)
       (where (even? ?w)) (compute ?d (+ ?w ?w)))
     (rule (summary ?r ?total)
       (root ?r) (reduce ?total (sum ?d) (score ?r ?d))))
   extra
   '((query summary 0 ?total) (limits 16 64 128))))

(def (reference-rich-summary edges)
  (let* ((reachable (reference-closure edges))
         (values
          (map (lambda (row)
                 (* 2 (cdr (assq (cadr row) '((1 . 4) (2 . 6))))))
               (filter
                (lambda (row)
                  (and (= (car row) 0)
                       (not (equal? row '(1 2)))
                       (assq (cadr row) '((1 . 4) (2 . 6)))))
                reachable))))
    (list (list 0 (apply + values)))))

(def (rich-snapshot generation edges)
  (reasoning-source-snapshot
   'rich-graph generation
   (list (list 'edge 2 edges)
         '(blocked 2 ((1 2)))
         '(weight 2 ((1 4) (2 6)))
         '(root 1 ((0))))))

;;; Twelve selected claims from seven revisions, plus pinned target Q30.
;;; Exact revision URLs and statement IDs are recorded in the research note.
;;; The city and target rows select a finite question universe; they are not
;;; asserted to be Wikidata statements. No open-world absence is inferred.
(def kg-cities '((Q100) (Q62) (Q18013)))
(def kg-target '((Q30)))
(def kg-admin
  '((Q100 Q54072) (Q54072 Q771) (Q771 Q30)
    (Q62 Q99) (Q18013 Q108131) (Q108131 Q99) (Q99 Q30)))
(def kg-direct-country '((Q100 Q30) (Q62 Q30) (Q18013 Q30)))
(def kg-state-capital '((Q771 Q100) (Q99 Q18013)))

(def (kg-snapshot generation direct)
  (reasoning-source-snapshot
   'wikidata-entity-revisions-2026-10-05 generation
   (list (list 'city 1 kg-cities)
         (list 'target 1 kg-target)
         (list 'admin 2 kg-admin)
         (list 'directCountry 2 direct)
         (list 'stateCapital 2 kg-state-capital))))

;;; Reference reachability walks source pairs, without rule admission,
;;; relational planning, or the candidate evaluator.
(def (kg-reaches? origin target edges)
  (let loop ((pending (list origin)) (seen []))
    (if (null? pending) #f
        (let (node (car pending))
          (cond
           ((equal? node target) #t)
           ((member node seen) (loop (cdr pending) seen))
           (else
            (loop (append (cdr pending)
                          (map cadr
                               (filter (lambda (row)
                                         (equal? (car row) node)) edges)))
                  (cons node seen))))))))

(def (kg-distinct rows)
  (let loop ((remaining rows) (seen []) (out []))
    (if (null? remaining) (reverse out)
        (let (row (car remaining))
          (if (member row seen)
            (loop (cdr remaining) seen out)
            (loop (cdr remaining) (cons row seen) (cons row out)))))))

(def (kg-check-rows actual expected)
  (check-equal? (length actual) (length (kg-distinct actual)))
  (check-equal? (same-rows? actual expected) #t))

(def (kg-reference direct)
  (kg-distinct
   (append
    (filter-map
     (lambda (city-row)
       (let (city (car city-row))
         (and (kg-reaches? city 'Q30 kg-admin)
              (not (member city (map cadr kg-state-capital)))
              (list city 'Q30))))
     kg-cities)
    (filter (lambda (row) (equal? (cadr row) 'Q30)) direct))))

(def kg-common-proposal
  '((relation adminPath 2)
    (relation viaAdmin 2)
    (relation excluded 1)
    (relation unionCandidate 2)
    (relation answer 2)
    (rule (adminPath ?x ?y) (admin ?x ?y))
    (rule (adminPath ?x ?z) (adminPath ?x ?y) (admin ?y ?z))
    (rule (viaAdmin ?city ?country)
          (city ?city) (adminPath ?city ?country) (target ?country))
    (rule (excluded ?city) (stateCapital ?state ?city))))

(def (kg-proposal scope query)
  (append
   (list 'candidate)
   kg-common-proposal
   (if (eq? scope 'branch)
     '((rule (answer ?city ?country)
             (viaAdmin ?city ?country) (not (excluded ?city)))
       (rule (answer ?city ?country)
             (directCountry ?city ?country) (target ?country)))
     '((rule (unionCandidate ?city ?country)
             (viaAdmin ?city ?country))
       (rule (unionCandidate ?city ?country)
             (directCountry ?city ?country) (target ?country))
       (rule (answer ?city ?country)
             (unionCandidate ?city ?country) (not (excluded ?city)))))
   (list query '(limits 32 128 256))))

(def (kg-scheme-program direct)
  (relational-program
   (relation city (item) kg-cities)
   (relation target (item) kg-target)
   (relation admin (child parent) kg-admin)
   (relation directCountry (city country) direct)
   (relation stateCapital (state city) kg-state-capital)
   (relation adminPath (child ancestor))
   (relation viaAdmin (city country))
   (relation excluded (city))
   (relation answer (city country))
   (rule (adminPath ?x ?y) (admin ?x ?y))
   (rule (adminPath ?x ?z) (adminPath ?x ?y) (admin ?y ?z))
   (rule (viaAdmin ?city ?country)
     (city ?city) (adminPath ?city ?country) (target ?country))
   (rule (excluded ?city) (stateCapital ?state ?city))
   (rule (answer ?city ?country)
     (viaAdmin ?city ?country) (not (excluded ?city)))
   (rule (answer ?city ?country)
     (directCountry ?city ?country) (target ?country))
   (limits 32 128 256)))

(def ascent-reasoning-library-test
  (test-suite "bounded inert reasoning library"
    (test-case "complete witness, absent cut, withdrawal, and retained receipt"
      (let* ((input (list (list 1 2) (list 2 3)))
             (first (edge-snapshot 1 input))
             (present (reasoning-attempt first (proposal 1 3)))
             (absent (reasoning-attempt first (proposal 1 4))))
        (check-equal? (reasoning-receipt-status present) 'complete)
        (check-equal? (reasoning-receipt-stratified present) #f)
        (check-equal? (reasoning-receipt-rows present) '((1 3)))
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence present)) 'witness)
        (check-equal? (reasoning-evidence-support
                       (reasoning-receipt-evidence present))
                      '((source 1 (1 2)) (source 2 (2 3))))
        (check-equal? (reasoning-receipt-status absent) 'complete)
        (check-equal? (reasoning-receipt-rows absent) '())
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence absent)) 'cut)
        (check-equal? (reasoning-evidence-reachable
                       (reasoning-receipt-evidence absent)) '(1 2 3))
        (set-car! (car input) 99)
        (check-equal? (reasoning-snapshot-digest first)
                      (reasoning-receipt-snapshot-digest present))
        (let* ((second (edge-snapshot 2 '((1 2))))
               (withdrawn (reasoning-attempt second (proposal 1 3))))
          (check-equal? (reasoning-receipt-snapshot-generation withdrawn) 2)
          (check-equal? (reasoning-receipt-rows withdrawn) '())
          (check-equal? (reasoning-evidence-kind
                         (reasoning-receipt-evidence withdrawn)) 'cut)
          (check-equal? (reasoning-receipt-rows present) '((1 3))))))
    (test-case "hypothetical source fact stays labelled and unpromoted"
      (let* ((snapshot (edge-snapshot 1 '((1 2) (2 3))))
             (candidate (proposal 1 4 (list (list 'fact 'edge 3 4))))
             (hypothesis
              (reasoning-attempt snapshot candidate))
             (without (reasoning-attempt snapshot (proposal 1 4))))
        (set-car! (cddr (list-ref candidate 4)) 99)
        (check-equal? (reasoning-receipt-rows hypothesis) '((1 4)))
        (check-equal? (reasoning-evidence-support
                       (reasoning-receipt-evidence hypothesis))
                      '((source 1 (1 2)) (source 2 (2 3))
                        (candidate 4 (3 4))))
        (check-equal? (reasoning-receipt-rows without) '())))
    (test-case "structural errors have paths"
      (let* ((snapshot (edge-snapshot 1 '((1 2))))
             (bad-helper
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (helper ?x ?y))
                           (query path 1 2) (limits 8 8 16))))
             (unsafe
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?z))
                           (query path 1 2) (limits 8 8 16))))
             (variable-fact
              (reasoning-attempt
               snapshot
               '(candidate (fact edge ?x 3)
                           (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?y))
                           (query path 1 2) (limits 8 8 16)))))
        (check-equal? (reasoning-receipt-status bad-helper) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic bad-helper)) 'unknown-relation)
        (check-equal? (reasoning-diagnostic-path
                       (first-diagnostic bad-helper)) '(clause 2 body 1))
        (check-equal? (reasoning-receipt-status unsafe) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic unsafe)) 'unbound-head-variable)
        (check-equal? (reasoning-diagnostic-path
                       (first-diagnostic unsafe)) '(clause 2 head term 2))
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic variable-fact)) 'invalid-fact)))
    (test-case "compiling wrong join is observed, not repaired"
      (let* ((snapshot (edge-snapshot 1 '((1 2) (2 3))))
             (wrong
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?y))
                           (rule (path ?x ?z)
                                 (path ?x ?y) (edge ?x ?z))
                           (query path 1 3) (limits 8 16 32)))))
        (check-equal? (reasoning-receipt-status wrong) 'complete)
        (check-equal? (reasoning-receipt-rows wrong) '())
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence wrong)) 'unsupported)))
    (test-case "bounded failure and source declaration validation"
      (let* ((snapshot (edge-snapshot 1 '((1 2) (2 3))))
             (bounded (reasoning-attempt snapshot
                                         (proposal 1 3 [] '(limits 8 1 32)))))
        (check-equal? (reasoning-receipt-status bounded) 'unknown)
        (check-exception
         (reasoning-source-snapshot 'graph 1 '((edge 2 ((1 2)))
                                               (edge 2 ((2 3))))) true)))
    (test-case "inert data preflight bounds cycles and depth before parsing"
      (let* ((snapshot (edge-snapshot 1 '((1 2))))
             (cycle (cons 'candidate [])))
        (set-cdr! cycle cycle)
        (let (receipt (reasoning-attempt snapshot cycle))
          (check-equal? (reasoning-receipt-status receipt) 'rejected)
          (check-equal? (reasoning-diagnostic-code
                         (first-diagnostic receipt)) 'invalid-candidate))
        (let (receipt
              (reasoning-attempt
               snapshot
               (let loop ((depth 0) (datum '(candidate)))
                 (if (= depth 200)
                   datum
                   (loop (+ depth 1) (list datum))))))
          (check-equal? (reasoning-receipt-status receipt) 'rejected))
        (check-equal?
         (reasoning-receipt-status
          (reasoning-attempt
           snapshot (cons 'candidate (make-list 20000 'relation))))
         'rejected)
        (check-equal?
         (reasoning-receipt-status
          (reasoning-attempt snapshot
                             (list 'candidate (lambda () 'run))))
         'rejected))
      (let (cycle (cons '(edge 2 ((1 2))) []))
        (set-cdr! cycle cycle)
        (check-exception
         (reasoning-source-snapshot 'graph 1 cycle) true)
        (check-equal?
         (reasoning-snapshot-valid?
          (make-reasoning-snapshot 'graph 1 "forged" cycle))
         #f))
      (let (row (list 1 2))
        (check-equal?
         (reasoning-snapshot-valid?
          (reasoning-source-snapshot
           'graph 1 (list (list 'edge 2 (list row row)))))
         #t)))
    (test-case "nonreflexive empty graph has complete unsupported evidence"
      (let* ((snapshot (edge-snapshot 1 '()))
             (candidate (proposal 1 1))
             (receipt (reasoning-attempt snapshot candidate 100000 20000))
             (stratified (reasoning-receipt-stratified receipt)))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-receipt-rows receipt) '())
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence receipt)) 'unsupported)
        (check-equal? (reasoning-stratified-evidence-status stratified)
                      'unsupported)
        (check-equal?
         (reasoning-verify-finite-receipt
          receipt snapshot candidate 20000) 'valid)
        (check-equal?
         (reasoning-verify-stratified-receipt
          receipt snapshot candidate 20000) 'unsupported)))
    (test-case "checked candidate clauses share trusted Scheme semantics"
      (let* ((snapshot
              (reasoning-source-snapshot
               'joined 1
               '((edge 2 ((1 2) (2 3)))
                 (blocked 2 ((1 3)))
                 (weight 2 ((2 4) (3 6)))
                 (root 1 ((1) (2))))))
             (candidate
              '(candidate
                 (relation path 2)
                 (relation allowed 2)
                 (relation weighted 2)
                 (relation summary 2)
                 (rule (path ?x ?y) (edge ?x ?y))
                 (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                 (rule (allowed ?x ?y)
                   (path ?x ?y) (not (blocked ?x ?y)))
                 (rule (weighted ?x ?v)
                   (allowed ?x ?y) (weight ?y ?w)
                   (where (even? ?w))
                   (compute ?v (+ ?w ?w)))
                 (rule (summary ?r ?n)
                   (root ?r)
                   (reduce ?n (count) (weighted ?r ?v)))
                 (query summary 1 ?n)
                 (limits 16 64 128)))
             (receipt (reasoning-attempt snapshot candidate 100000 20000)))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-receipt-rows receipt) '((1 1)))
        (check-equal? (reasoning-evidence-kind
                       (reasoning-receipt-evidence receipt)) 'unsupported)
        (check-equal?
         (reasoning-stratified-evidence-status
          (reasoning-receipt-stratified receipt)) 'complete)
        (check-equal?
         (reasoning-verify-stratified-receipt
          receipt snapshot candidate 20000) 'valid)
        (check-equal?
         (reasoning-receipt-rows
          (reasoning-attempt
           snapshot
           '(candidate
              (relation path 2)
              (rule (path ?x ?y) (edge ?x ?y)
                    (not (blocked ?x ?y)))
              (query path 1 ?y) (limits 16 32 64))))
         '((1 2)))))
    (test-case "optional receipt proof follows source and candidate binding"
      (let* ((first (rich-snapshot 1 '((0 1) (1 2))))
             (second (rich-snapshot 2 '((0 1))))
             (candidate (rich-proposal '?y))
             (first-receipt
              (reasoning-attempt first candidate 100000 20000))
             (second-receipt
              (reasoning-attempt second candidate 100000 20000))
             (bounded
              (reasoning-attempt first candidate 100000 1))
             (rejected
              (reasoning-attempt
               first
               '(candidate (relation x 1)
                           (rule (x ?x) (missing ?x))
                           (query x ?x) (limits 8 8 16))
               100000 20000)))
        (check-equal? (reasoning-receipt-rows first-receipt) '((0 20)))
        (check-equal? (reasoning-receipt-rows second-receipt) '((0 8)))
        (check-equal? (reasoning-receipt-status bounded) 'complete)
        (check-equal?
         (reasoning-stratified-evidence-status
          (reasoning-receipt-stratified bounded)) 'bounded)
        (check-equal?
         (reasoning-verify-stratified-receipt bounded first candidate 20000)
         'bounded)
        (check-equal?
         (reasoning-verify-stratified-receipt
          first-receipt first candidate 20000) 'valid)
        (check-equal?
         (reasoning-verify-stratified-receipt
          second-receipt second candidate 20000) 'valid)
        (check-equal?
         (reasoning-verify-stratified-receipt
          first-receipt second candidate 20000) 'invalid)
        (check-equal?
         (reasoning-verify-stratified-receipt
          first-receipt first (rich-proposal '?x) 20000) 'invalid)
        (check-equal? (reasoning-receipt-stratified rejected) #f)
        (check-equal?
         (reasoning-verify-stratified-receipt
          rejected first candidate 20000) 'invalid)
        (check-equal?
         (reasoning-verify-finite-receipt
          first-receipt first candidate 1) 'bounded)
        (let (proof
              (reasoning-stratified-evidence-proof
               (reasoning-receipt-stratified first-receipt)))
          (set-car! (caddr proof) 999)
          (check-equal?
           (reasoning-verify-stratified-receipt
            first-receipt first candidate 20000) 'invalid))
        (set-car!
         (cddr
          (assq 'path
                (finite-evidence-closure
                 (reasoning-stratified-evidence-finite
                  (reasoning-receipt-stratified second-receipt)))))
         '((99 99)))
        (check-equal?
         (reasoning-verify-stratified-receipt
          second-receipt second candidate 20000) 'invalid)))
    (test-case "scripted feedback revision stays bound to exact source and proposal"
      (let* ((first (rich-snapshot 1 '((0 1) (1 2))))
             (invalid
              '(candidate (relation path 2)
                          (rule (path ?x ?y) (missing ?x ?y))
                          (query path 0 2) (limits 16 64 128)))
             (wrong (rich-proposal '?x))
             (correct (rich-proposal '?y))
             (rejected (reasoning-attempt first invalid))
             (wrong-answer (reasoning-attempt first wrong))
             (correct-answer (reasoning-attempt first correct))
             (second (rich-snapshot 2 '((0 1))))
             (withdrawn (reasoning-attempt second correct))
             (hypothesis (rich-proposal '?y '((fact edge 0 2))))
             (overlay (reasoning-attempt second hypothesis))
             (base-again (reasoning-attempt second correct)))
        (check-equal? (reasoning-receipt-status rejected) 'rejected)
        (check-equal? (reasoning-receipt-bound? rejected first invalid) #t)
        (check-equal? (reasoning-receipt-bound? rejected first correct) #f)
        (check-equal? (reasoning-receipt-status wrong-answer) 'complete)
        (check-equal? (reasoning-receipt-rows wrong-answer) '((0 8)))
        (check-equal? (reasoning-receipt-bound? wrong-answer first wrong) #t)
        (check-equal? (reasoning-receipt-bound? wrong-answer first correct) #f)
        (check-equal? (reasoning-receipt-status correct-answer) 'complete)
        (check-equal? (reasoning-receipt-rows correct-answer)
                      (reference-rich-summary '((0 1) (1 2))))
        (check-equal? (reasoning-receipt-bound? correct-answer first correct)
                      #t)
        (check-equal? (reasoning-receipt-bound? correct-answer second correct)
                      #f)
        (check-equal? (reasoning-receipt-rows withdrawn)
                      (reference-rich-summary '((0 1))))
        (check-equal? (reasoning-receipt-rows overlay)
                      (reference-rich-summary '((0 1) (0 2))))
        (check-equal? (reasoning-receipt-rows base-again)
                      (reasoning-receipt-rows withdrawn))
        (check-equal? (reasoning-receipt-bound? overlay second hypothesis)
                      #t)
        (set-car! (cadr wrong) 'altered)
        (check-equal? (reasoning-receipt-bound? wrong-answer first wrong)
                      #f)))
    (test-case "candidate modes and stratification reject at their boundary"
      (let* ((snapshot (edge-snapshot 1 '((1 2))))
             (unsafe
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (not (edge ?x ?y)))
                           (query path ?x ?y) (limits 8 8 16))))
             (unbound
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?v) (edge ?x ?y)
                                 (compute ?v (+ ?w ?w)))
                           (query path ?x ?v) (limits 8 8 16))))
             (cycle
              (reasoning-attempt
               snapshot
               '(candidate (relation path 2)
                           (rule (path ?x ?y) (edge ?x ?y)
                                 (not (path ?x ?y)))
                           (query path ?x ?y) (limits 8 8 16)))))
        (check-equal? (reasoning-receipt-status unsafe) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic unsafe)) 'unsafe-negation)
        (check-equal? (reasoning-diagnostic-path
                       (first-diagnostic unsafe)) '(clause 2 body 1 term 1))
        (check-equal? (reasoning-receipt-status unbound) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic unbound)) 'unbound-operator-input)
        (check-equal? (reasoning-receipt-status cycle) 'rejected)
        (check-equal? (reasoning-diagnostic-code
                       (first-diagnostic cycle)) 'invalid-dependencies)))
    (test-case "fixed Wikidata entity extract preserves branch-scoped exclusion"
      (let* ((withdrawn-direct '((Q62 Q30) (Q18013 Q30)))
             (first-source (kg-snapshot 1 kg-direct-country))
             (second-source (kg-snapshot 2 withdrawn-direct))
             (gold (kg-proposal 'branch '(query answer ?city Q30)))
             (positive (kg-proposal 'branch '(query viaAdmin ?city Q30)))
             (global (kg-proposal 'global '(query answer ?city Q30)))
             (first (reasoning-attempt first-source gold 100000 20000))
             (second (reasoning-attempt second-source gold 100000 20000))
             (path (reasoning-attempt first-source positive 100000 20000))
             (wrong (reasoning-attempt first-source global 100000 20000))
             (evidence (reasoning-receipt-stratified first)))
        ;; The separate set model has a hard-coded, inspectable expectation.
        (kg-check-rows (kg-reference kg-direct-country)
                       '((Q100 Q30) (Q62 Q30) (Q18013 Q30)))
        (kg-check-rows (kg-reference withdrawn-direct)
                       '((Q62 Q30) (Q18013 Q30)))
        (for-each
         (lambda (receipt)
           (check-equal? (reasoning-receipt-status receipt) 'complete))
         (list first second path wrong))
        (kg-check-rows (reasoning-receipt-rows path)
                       '((Q100 Q30) (Q62 Q30) (Q18013 Q30)))
        (kg-check-rows (reasoning-receipt-rows first)
                       (kg-reference kg-direct-country))
        ;; Applying negation after the union loses both direct witnesses.
        (kg-check-rows (reasoning-receipt-rows wrong) '((Q62 Q30)))
        (kg-check-rows (reasoning-receipt-rows second)
                       (kg-reference withdrawn-direct))
        (check-equal? (reasoning-stratified-evidence-status evidence)
                      'complete)
        (let (closure (finite-evidence-closure
                      (reasoning-stratified-evidence-finite evidence)))
          (kg-check-rows (caddr (assq 'viaAdmin closure))
                         '((Q100 Q30) (Q62 Q30) (Q18013 Q30)))
          (kg-check-rows (caddr (assq 'excluded closure))
                         '((Q100) (Q18013))))
        (check-equal?
         (reasoning-verify-stratified-receipt
          first first-source gold 20000) 'valid)
        (check-equal?
         (reasoning-verify-stratified-receipt
          second second-source gold 20000) 'valid)
        (check-equal? (reasoning-receipt-bound? first second-source gold) #f)
        (check-equal?
         (reasoning-verify-stratified-receipt
          first second-source gold 20000) 'invalid)
        (let* ((session (relational-open-program-session
                         (kg-scheme-program kg-direct-country)))
               (old (relational-program-session-run session)))
          (relational-program-replace-source!
           session 'directCountry withdrawn-direct)
          (let (new (relational-program-session-run session))
            (kg-check-rows (relational-program-query old 'answer)
                           (kg-reference kg-direct-country))
            (kg-check-rows (relational-program-query new 'answer)
                           (kg-reference withdrawn-direct))
            (kg-check-rows (relational-program-query old 'answer)
                           (kg-reference kg-direct-country))))))
    (test-case "all sixty-four three-node graphs match finite reference"
      (let (possible '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
        (for-each
         (lambda (mask)
           (let* ((edges
                   (let loop ((remaining possible) (bit 1) (rows []))
                     (if (null? remaining)
                       (reverse rows)
                       (loop (cdr remaining) (* bit 2)
                             (if (zero? (bitwise-and mask bit)) rows
                               (cons (car remaining) rows))))))
                  (receipt
                   (reasoning-attempt
                    (edge-snapshot mask edges)
                    (proposal '?from '?to [] '(limits 8 16 32)))))
             (check-equal? (reasoning-receipt-status receipt) 'complete)
             (check-equal?
              (same-rows? (reasoning-receipt-rows receipt)
                          (reference-closure edges)) #t)
             (when (zero? (modulo (+ mask 1) 8))
               (displayln "REASONING-GRAPHS-CHECKED " (+ mask 1) "/64")
               (force-output))))
         (iota 64))))))
