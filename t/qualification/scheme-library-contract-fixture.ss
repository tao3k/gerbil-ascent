;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One finite specification for the common native/candidate subset.
;;; The matrix below does not call an ASCENT evaluator to obtain expectations.
(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :gerbil-ascent/program/interface
                 relational-program relational-fragment relational-compose
                 relational-admit relational-solve relational-query-name
                 relational-query relational-open-program-session
                 relational-program-session-run relational-program-transaction!
                 relational-program-query)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-bound?
                 reasoning-receipt-stratified
                 reasoning-stratified-evidence-status
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))

(export #t)

(def vertices '(0 1 2))
(def possible-edges '((0 1) (0 2) (1 0) (1 2) (2 0) (2 1)))
(def weights '((0 2) (1 4) (2 6)))
(def roots '((0) (1) (2)))
(def support-phases '(((0 1) (1 2) (0 2))
                      ((0 1) (1 2)) ((0 1)) ((0 2))))
(def support-totals '(20 20 8 12))

(def study-cases
  (append (map (lambda (edges) (list edges '() weights '((0)))) support-phases)
          (list (list (car support-phases) '((0 2)) weights '((0)))
                (list (car support-phases) '() '((0 2) (1 3) (2 6)) '((0)))
                (list (car support-phases) '() '((0 2) (1 4) (2 4)) '((0))))))

(def (edges-for-mask mask)
  (let loop ((i 0) (rest possible-edges) (rows []))
    (if (null? rest)
      (reverse rows)
      (loop (+ i 1) (cdr rest)
            (if (not (zero? (bitwise-and mask (arithmetic-shift 1 i))))
              (cons (car rest) rows) rows)))))

(def (same-set? actual expected)
  (and (= (length actual) (length expected))
       (andmap (lambda (row) (if (member row expected) #t #f)) actual)
       (andmap (lambda (row) (if (member row actual) #t #f)) expected)))

(def (unique-values values)
  (foldl (lambda (value prior) (if (memv value prior) prior (cons value prior))) [] values))

(def (model-paths edges)
  (let (matrix (make-vector 9 #f))
    (def (index from to) (+ (* 3 from) to))
    (for-each (lambda (edge)
                (vector-set! matrix (index (car edge) (cadr edge)) #t))
              edges)
    (for-each
     (lambda (via)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (when (and (vector-ref matrix (index from via))
                        (vector-ref matrix (index via to)))
               (vector-set! matrix (index from to) #t)))
           vertices))
        vertices))
     vertices)
    (apply append
           (map (lambda (from)
                  (map (lambda (to) (list from to))
                       (filter (lambda (to) (vector-ref matrix (index from to))) vertices)))
                vertices))))

(def (model-summary edges blocked supplied-weights supplied-roots)
  (let (paths (model-paths edges))
    (map
     (lambda (root)
       (let (origin (car root))
         (list origin
               (apply +
                      (unique-values (map (lambda (weight) (* 2 (cadr weight)))
                           (filter
                            (lambda (weight)
                              (and (even? (cadr weight))
                                   (member (list origin (car weight)) paths)
                                   (not (member
                                         (list origin (car weight))
                                         blocked))))
                            supplied-weights)))))))
     supplied-roots)))

(def (unique-rows rows)
  (foldl (lambda (row prior) (if (member row prior) prior (cons row prior))) [] rows))

(def (model-relations edges blocked supplied-weights supplied-roots)
  (let* ((paths (model-paths edges))
         (allowed (filter (lambda (row) (not (member row blocked))) paths))
         (weighted
          (unique-rows
           (apply append
                  (map (lambda (row)
                         (map (lambda (weight) (list (car row) (* 2 (cadr weight))))
                              (filter (lambda (weight)
                                        (and (= (car weight) (cadr row))
                                             (even? (cadr weight))))
                                      supplied-weights)))
                       allowed)))))
    (map cons '(edge blocked weight root path allowed weighted summary)
         (list (unique-rows edges) (unique-rows blocked)
               (unique-rows supplied-weights) (unique-rows supplied-roots)
               paths allowed weighted
               (model-summary edges blocked supplied-weights supplied-roots)))))

(def (native-program edges blocked supplied-weights supplied-roots)
  (relational-program
   (relation edge (from to) edges)
   (relation blocked (from to) blocked)
   (relation weight (node value) supplied-weights)
   (relation root (node) supplied-roots)
   (relation path (from to))
   (relation allowed (from to))
   (relation weighted (from value))
   (relation summary (node total))
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
   (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
   (rule (weighted ?x ?v)
     (allowed ?x ?y) (weight ?y ?w)
     (where (even? ?w)) (compute ?v (+ ?w ?w)))
   (rule (summary ?r ?n)
     (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))
   (limits 16 64 128)))

(def (fragment-program edges blocked-rows supplied-weights supplied-roots)
  (relational-fragment
   (import)
   (source (edge (from to) edges)
           (blocked (from to) blocked-rows)
           (weight (node value) supplied-weights)
           (root (node) supplied-roots))
   (private (path (from to)) (allowed (from to))
            (weighted (from value)) (summary (node total)))
   (export (summary summary))
   (rule (path ?x ?y) (edge ?x ?y))
   (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
   (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
   (rule (weighted ?x ?v)
     (allowed ?x ?y) (weight ?y ?w)
     (where (even? ?w)) (compute ?v (+ ?w ?w)))
   (rule (summary ?r ?n)
     (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))))

(def candidate
  '(candidate
     (relation path 2) (relation allowed 2)
     (relation weighted 2) (relation summary 2)
     (rule (path ?x ?y) (edge ?x ?y))
     (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
     (rule (allowed ?x ?y) (path ?x ?y) (not (blocked ?x ?y)))
     (rule (weighted ?x ?v)
       (allowed ?x ?y) (weight ?y ?w)
       (where (even? ?w)) (compute ?v (+ ?w ?w)))
     (rule (summary ?r ?n)
       (root ?r) (reduce ?n (sum ?v) (weighted ?r ?v)))
     (query summary ?r ?n) (limits 16 64 128)))

(def (replace-rule proposal head replacement)
  (map (lambda (clause)
         (if (and (pair? clause) (eq? (car clause) 'rule)
                  (eq? (caadr clause) head)) replacement clause)) proposal))

(def study-repair-seed
  (replace-rule candidate 'weighted
    '(rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
       (where (even? ?w)) (compute ?v + ?w ?w))))

(def study-filter-seed
  (replace-rule candidate 'weighted
    '(rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
       (where even? ?w) (compute ?v (+ ?w ?w)))))

(def study-mutants
  (list
   (cons 'missing-negation
     (replace-rule candidate 'allowed
       '(rule (allowed ?x ?y) (path ?x ?y))))
   (cons 'missing-guard
     (replace-rule candidate 'weighted
       '(rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
          (compute ?v (+ ?w ?w)))))
   (cons 'guard-after-doubling
     (replace-rule candidate 'weighted
       '(rule (weighted ?x ?v) (allowed ?x ?y) (weight ?y ?w)
          (compute ?v (+ ?w ?w)) (where (even? ?v)))))))

(def (contract-snapshot generation edges blocked supplied-weights supplied-roots)
  (reasoning-source-snapshot
   'contract generation
   (list (list 'edge 2 edges) (list 'blocked 2 blocked)
         (list 'weight 2 supplied-weights) (list 'root 1 supplied-roots))))

(def (candidate-result generation edges blocked supplied-weights supplied-roots)
  (let* ((snapshot
          (contract-snapshot generation edges blocked supplied-weights
                             supplied-roots))
         (receipt (reasoning-attempt snapshot candidate 100000 20000)))
    (check-equal? (reasoning-receipt-status receipt) 'complete)
    (check-equal? (reasoning-receipt-bound? receipt snapshot candidate) #t)
    (check-equal?
     (reasoning-stratified-evidence-status
      (reasoning-receipt-stratified receipt)) 'complete)
    (check-equal?
     (reasoning-verify-finite-receipt receipt snapshot candidate 20000) 'valid)
    (check-equal?
     (reasoning-verify-stratified-receipt
      receipt snapshot candidate 20000) 'valid)
    (reasoning-receipt-rows receipt)))

(def (check-all generation edges blocked supplied-weights supplied-roots)
  (let* ((expected (model-summary edges blocked supplied-weights supplied-roots))
         (direct (relational-query-name
                  (relational-solve (relational-admit
                    (native-program edges blocked supplied-weights supplied-roots)))
                  'summary)))
    (check-equal? (same-set? direct expected) #t)
    (displayln "CONTRACT-CHECKED direct " generation) (force-output)
    (let* ((fragment (fragment-program edges blocked supplied-weights supplied-roots))
           (composed (relational-query
                      (relational-solve (relational-admit
                        (relational-compose (list fragment) 16 64 128)))
                      fragment 'summary)))
      (check-equal? (same-set? composed expected) #t)
      (displayln "CONTRACT-CHECKED composed " generation) (force-output))
    (check-equal? (same-set?
                   (candidate-result generation edges blocked supplied-weights supplied-roots)
                   expected) #t)
    (displayln "CONTRACT-CHECKED candidate " generation) (force-output)))

;;; The same composed application across cold construction, source updates,
;;; candidate evidence production and replay. No preinitialized Session is
;;; supplied to either arm. Candidate work is identical in both arms.
(def lifecycle-states
  (append study-cases
          (list (list '((0 1) (1 2) (2 0)) '() weights '((0)))
                (list '() '() weights '((0))))))

(def (application-lifecycle retained?)
  (let ((session #f) (results (make-vector (length lifecycle-states) #f)))
    (for-each
     (lambda (generation state)
       (let (native
             (if (and retained? session)
               (relational-program-transaction!
                session (map cons '(edge blocked weight root) state))
               (begin
                 (set! session
                       (relational-open-program-session
                        (apply native-program state)))
                 (relational-program-session-run session))))
         (vector-set! results generation
                      (list native (apply candidate-result generation state)))
         ;; Genuine completed work, identical output cost in both arms.
         (displayln "APPLICATION-COMPLETED arm=" (if retained? 'retained 'fresh)
                    " state=" generation)
         (force-output)))
     (iota (length lifecycle-states)) lifecycle-states)
    (vector results session)))

(def (check-lifecycle measured)
  (let* ((results (vector-ref measured 0)) (session (vector-ref measured 1))
         (last (- (vector-length results) 1)))
    (check-exception
     (relational-program-transaction! session '((edge (0)))) true)
    (let (after-failure (relational-program-session-run session))
      (for-each
       (lambda (binding)
         (check-equal?
          (same-set? (relational-program-query after-failure (car binding))
                     (cdr binding)) #t))
       (apply model-relations (list-ref lifecycle-states last))))
    ;; Check every old published snapshot after the full sequence and a
    ;; rejected transaction, not just the latest answer.
    (for-each
     (lambda (generation state)
       (let* ((observed (vector-ref results generation))
              (expected (apply model-summary state)))
         ;; Public Session APIs return completed solution wrappers; bounded
         ;; native results throw before that wrapper is constructed.
         (for-each
          (lambda (binding)
            (check-equal?
             (same-set? (relational-program-query (car observed) (car binding))
                        (cdr binding)) #t))
          (apply model-relations state))
         (check-equal? (same-set? (cadr observed) expected) #t)))
     (iota (length lifecycle-states)) lifecycle-states)))

(def (sample-lifecycle retained?)
  (let (counter (make-f64vector 2 0.0))
    (##gc)
    (let ((wall (current-jiffy)) (cpu (cpu-time)))
      (##get-bytes-allocated! counter 0)
      (let (result (application-lifecycle retained?))
        (##get-bytes-allocated! counter 1)
        (let ((cpu-us (* 1000000 (- (cpu-time) cpu)))
              (wall-us (* 1000000 (/ (- (current-jiffy) wall) (jiffies-per-second))))
              (bytes (- (f64vector-ref counter 1) (f64vector-ref counter 0))))
          (check-equal? (>= bytes 0) #t)
          (check-lifecycle result)
          (vector cpu-us wall-us bytes))))))
