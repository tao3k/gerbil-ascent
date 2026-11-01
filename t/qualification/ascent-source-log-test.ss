;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (prefix-in :clan/poo/testing/property property.)
        (prefix-in :clan/poo/testing/property/generator generator.)
        (prefix-in :clan/poo/testing/property/replay replay.)
        (only-in :clan/poo/testing/property/test require-passed)
        (only-in :gerbil-ascent/program/scheme-language relational-program)
        (only-in :gerbil-ascent/t/qualification/fixtures/semi-naive/oracle finite-domain-closure)
        :gerbil-ascent/program/source-log
        :gerbil-ascent/t/performance/source-log/fixture
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session gerbil-ascent-session-run
                 gerbil-ascent-session-replace-sources! gerbil-ascent-session-append-source!))
(export ascent-source-log-test)
(def (words depth)
  (if (zero? depth) (list [])
    (cons [] (foldr (lambda (word rest) (cons (cons '(#f) word) (cons (cons '(0) word) rest))) [] (words (- depth 1))))))
(def log-rows-generator
  (generator.generator-list (generator.generator-elements '((#f) (0) (1))) max-length: 16))
(def log-comparison-generator
  (generator.generator-map
   (generator.generator-sequence
    (list log-rows-generator log-rows-generator (generator.generator-integer-range 0 3)))
   (lambda (parts)
     (let* ((base (car parts)) (additions (cadr parts)) (whole (append base (reverse additions)))
            (candidate (case (caddr parts)
                         ((0) whole) ((1) (cons '(different) whole))
                         ((2) (if (null? whole) '((different))
                                  (append (take whole (- (length whole) 1)) '((different)))))
                         (else (if (null? whole) '((different)) (cdr whole))))))
       (list base additions candidate)))))
(def log-comparison-domain
  (property.make-specification
   (lambda (parts) (and (list? parts) (= (length parts) 3)
                       (andmap (lambda (rows) (and (list? rows) (<= (length rows) 33)
                         (andmap (lambda (row) (and (list? row) (= (length row) 1)
                                                    (and (memv (car row) '(#f 0 1 different)) #t))) rows))) parts)))
   (lambda (parts) (foldl (lambda (rows n) (+ n (length rows))) 0 parts))))
(def log-comparison-codec (replay.make-codec '(ascent-ordered-log (parts 3) (rows 33)) values values))
(def (log-comparison-property parts)
  (eq? (gerbil-ascent-source-log-equal? (car parts) (cadr parts) (caddr parts))
       (equal? (append (car parts) (reverse (cadr parts))) (caddr parts))))
(def (log-labels parts)
  (let ((base (car parts)) (additions (cadr parts)) (candidate (caddr parts)))
    (filter values (list
      (and (equal? (append base (reverse additions)) candidate) 'equal-log)
      (and (pair? base) (pair? candidate) (not (equal? (car base) (car candidate))) 'first-mismatch)
      (and (pair? base) (pair? candidate) (equal? (car base) (car candidate))
           (not (equal? (append base (reverse additions)) candidate)) 'later-mismatch)
      (and (pair? additions) 'nonempty-additions)
      (and (member '(#f) (append base additions)) 'false-row)))))
(def ascent-source-log-test
  (test-suite "Persistent ordered source logs"
    (test-case "POO ordered-log PBT checks early and late mismatches against concatenation"
      (let (report (property.check-property log-comparison-generator log-comparison-property log-comparison-domain
                     seed: 20261101 cases: 128 size: 16 shrink-budget: 64
                     policy: (property.make-policy name: 'ascent-ordered-log-prefix
                               labels: log-labels required: '((equal-log . 1) (first-mismatch . 1)
                                  (later-mismatch . 1) (nonempty-additions . 1) (false-row . 1)))))
        (displayln "POO-SOURCE-LOG-PBT " (property.report-diagnostics report))
        (when (eq? (property.report-status report) 'failed)
          (replay.write-counterexample report log-comparison-codec (current-output-port)))
        (require-passed report)
        (check-equal? (property.report-accepted report) 128)
        (check-equal? (property.report-discarded report) 0)))
    (test-case "closed DSL Sessions isolate updates while held snapshots remain unchanged"
      (let* ((edges '((0 1) (1 2)))
             (program (relational-program
                       (relation edge (a b) edges) (relation path (a b))
                       (rule (path ?x ?y) (edge ?x ?y))
                       (rule (path ?x ?z) (path ?x ?y) (edge ?y ?z))
                       (limits 16 64 128)))
             (parent (gerbil-ascent-open-session program))
             (a (gerbil-ascent-open-session program)) (b (gerbil-ascent-open-session program))
             (held (gerbil-ascent-session-run parent))
             (a-held (gerbil-ascent-session-run a)) (b-held (gerbil-ascent-session-run b)))
        (def (check-paths result source)
          (let* ((expected (cdr (assq 'path (finite-domain-closure '(0 1 2 3)
                              (list (cons 'edge source) '(path))
                              '(((path x y) (edge x y)) ((path x z) (path x y) (edge y z)))))))
                 (actual ((.ref result 'rows-of) 'path)))
            (check-equal? (length actual) (length expected))
            (check-equal? (andmap (lambda (row) (and (member row expected) #t)) actual) #t)))
        (check-equal? (eq? held (gerbil-ascent-session-run parent)) #t)
        (gerbil-ascent-session-append-source! a 'edge '(2 3))
        (check-paths (gerbil-ascent-session-run a) '((0 1) (1 2) (2 3)))
        (gerbil-ascent-session-replace-sources! b '((edge (3 0))))
        (check-paths (gerbil-ascent-session-run b) '((3 0)))
        (for-each (lambda (result) (check-paths result edges)) (list held a-held b-held))
        (check-equal? (eq? held (gerbil-ascent-session-run parent)) #t)
        (gerbil-ascent-session-replace-sources! a '((edge (0 1) (1 2))))
        (check-paths (gerbil-ascent-session-run a) edges)
        (check-paths (gerbil-ascent-session-run b) '((3 0)))))
    (test-case "675 finite cases retain exact order multiplicity and false values"
      (for-each
       (lambda (base)
         (for-each
          (lambda (additions)
            (let (expected (append base (reverse additions)))
              (check-equal? (gerbil-ascent-source-log-rows base additions) expected)
              (for-each
               (lambda (candidate)
                 (check-equal? (gerbil-ascent-source-log-equal? base additions candidate)
                               (equal? expected candidate)))
               (list expected (cons '(extra) expected) (if (pair? expected) (cdr expected) '((extra)))))))
          (words 3))) (words 3)))
    (test-case "read-only base reuse and detached appended headers preserve row identity"
      (let* ((row (list #f)) (last (list 2)) (base (list row)) (additions (list last))
             (joined (gerbil-ascent-source-log-rows base additions)))
        (check-equal? (eq? (gerbil-ascent-source-log-rows base []) base) #t)
        (check-equal? (eq? (car joined) row) #t)
        (check-equal? (eq? (cadr joined) last) #t)
        (set-car! joined '(changed))
        (check-equal? base (list row))
        (check-equal? additions (list last))))
    (test-case "public replacements retain appended sources and prior snapshots"
      (for-each
       (lambda (old?)
         (let* ((program (source-log-program 8 32))
                (session (source-log-request old? program #t))
                (prior (gerbil-ascent-session-run session))
                (before (source-log-result prior 8)))
           (for-each
            (lambda (_)
              (let (result (source-log-update session 8))
                (check-equal? (car result) #t)
                (check-equal? (list-ref (caddr result) 1) (append (map list (iota 32)) '((9999))))
                (check-equal? (drop (caddr result) 2) (make-list 6 (map list (iota 32)))))
              (check-equal? (source-log-result prior 8) before)) (iota 4))
           (let ((rows (list (list 55))))
             (gerbil-ascent-session-replace-sources! session (list (cons 'r0 rows)))
             (set-car! (car rows) 'mutated)
             (check-equal? ((.ref (gerbil-ascent-session-run session) 'rows-of) 'r0) '((55)))))) '(#t #f)))))
