;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/program/rule-body make-rule-body-visitor)
        (only-in :std/test test-suite test-case check-equal? check-exception)
        (only-in :clan/poo/object .ref .o)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-fragment relational-compose relational-export
                 relational-admit relational-admit/report relational-solve relational-query-name
                 relational-query relational-open-program-session relational-program-session-run
                 relational-program-query relational-program-append-source!
                 relational-program-replace-source! relational-admission-report-admission
                 relational-admission-report-diagnostic relational-diagnostic-code
                 relational-diagnostic-path relational-diagnostic-origin)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-finite-source relational-relation-role)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program)
        (only-in :gerbil-ascent/program/types gerbil-ascent-projection-tree-current?
                 gerbil-ascent-rule-with-origin))
(export scheme-declaration-contract-test)

(def (role-program rows)
  (relational-program
   (relation edge (x y) rows (role input) (domain '((1 2 3) (1 2 3))))
   (relation reach (x y) '() (role derived) (domain '((1 2 3) (1 2 3))))
   (rule (reach ?x ?y) (edge ?x ?y))
   (rule (reach ?x ?z) (reach ?x ?y) (edge ?y ?z))
   (limits 16 32 64)))

(def scheme-declaration-contract-test
  (test-suite "Checked declaration roles, domains and source diagnostics"
    (test-case "ordered host traversal counts only positive atoms as delta positions"
      (let* ((trace '())
             (visit (make-rule-body-visitor
                     (lambda (atom environment delta? terms)
                       (set! trace (cons (list (vector-ref atom 0) delta?) trace))
                       (if (= (vector-ref atom 0) 2) '() '((1))))))
             (a (vector 0 #f #f '((variable . x))))
             (b (vector 1 #f #f '((variable . x))))
             (n (vector 2 #f #f '((variable . x))))
             (results '()))
        (visit (list (vector 'atom a)
                     (vector 'binding 'y '(x) (lambda (x) (+ x 1)))
                     (vector 'negation n) (vector 'atom b))
               1 0 '() (lambda (env) (set! results (cons env results))))
        (check-equal? (reverse trace) '((0 #f) (2 #f) (1 #t)))
        (check-equal? results '(((y . 2) (x . 1))))))
    (test-case "failed guards and negation suppress subsequent host callbacks"
      (let* ((calls 0)
             (visit (make-rule-body-visitor (lambda args '((1)))))
             (later (vector 'binding 'y '() (lambda () (set! calls (+ calls 1)) 9))))
        (visit (list (vector 'guard '() (lambda () #f)) later) -1 0 '() values)
        (visit (list (vector 'negation (vector 0 #f #f '((variable . x)))) later)
               -1 0 '() values)
        (check-equal? calls 0)))
    (test-case "invalid aggregate output fails before downstream callbacks"
      (let* ((calls 0)
             (visit (make-rule-body-visitor (lambda args '((1)))))
             (aggregate (vector 'aggregate (vector 0 #f #f '((variable . x)))
                                'y '(x) (lambda (tuples) #f) #f)))
        (check-exception
         (visit (list aggregate) -1 0 '()
                (lambda (env) (set! calls (+ calls 1)))) true)
        (check-equal? calls 0)))
    (test-case "explicit roles determine handles independently of initial emptiness"
      (let (program (role-program '()))
        (check-equal? (.ref program 'source-handles) '(edge))
        (check-equal? (map relational-relation-role (.ref program 'relations)) '(input derived))
        (let (session (relational-open-program-session program))
          (check-equal? (relational-program-query (relational-program-session-run session) 'reach) '())
          (relational-program-append-source! session 'edge '(1 2))
          (check-equal? (relational-program-query (relational-program-session-run session) 'reach) '((1 2)))
          (check-exception (relational-program-append-source! session 'reach '(2 3)) true)
          (check-equal? (relational-program-query (relational-program-session-run session) 'reach) '((1 2))))))
    (test-case "metadata views retain factory structure without certifying caller objects"
      (let* ((program (role-program '()))
             (rules (.ref program 'rules))
             (foreign (.o (:: @ (car rules)) body: (.ref (car rules) 'body)))
             (view (gerbil-ascent-rule-with-origin foreign #f))
             (replacement (gerbil-ascent-program (.ref program 'relations) (cons view (cdr rules))
                            16 32 64 (.ref program 'source-handles))))
        (check-equal? (and (gerbil-ascent-projection-tree-current? program) #t) #t)
        (check-equal? (and (gerbil-ascent-projection-tree-current? replacement) #t) #f)))
    (test-case "direct and fragment declarations agree with an independent chain closure"
      (let* ((fragment
              (relational-fragment
               (import)
               (source (edge (x y) '((1 2) (2 3)) (domain '((1 2 3) (1 2 3))) (role input)))
               (private (reach (x y) (domain '((1 2 3) (1 2 3)))))
               (export (answer reach))
               (rule (reach ?x ?y) (edge ?x ?y))
               (rule (reach ?x ?z) (reach ?x ?y) (edge ?y ?z))))
             (composed (relational-compose (list fragment) 16 32 64))
             (direct (relational-solve (relational-admit (role-program '((1 2) (2 3)))))))
        (let (rows (relational-query (relational-solve (relational-admit composed)) fragment 'answer))
          (check-equal? (length rows) 3)
          (for-each (lambda (row) (check-equal? (and (member row rows) #t) #t)) '((1 2) (2 3) (1 3)))
          (check-equal? rows (relational-query-name direct 'reach)))))
    (test-case "mixed relations keep base facts and rules across source replacement"
      (let* ((program
              (relational-program
               (relation edge (x y) '((1 2)) (role input))
               (relation reach (x y) '((2 3)) (role mixed))
               (rule (reach ?x ?y) (edge ?x ?y))
               (limits 16 32 64)))
             (session (relational-open-program-session program)))
        (check-equal? (.ref program 'source-handles) '(edge reach))
        (check-equal? (length (relational-program-query (relational-program-session-run session) 'reach)) 2)
        (relational-program-replace-source! session 'reach '())
        (check-equal? (relational-program-query (relational-program-session-run session) 'reach) '((1 2)))))
    (test-case "domain annotations reuse the existing constructor and capture inputs once"
      (let ((calls 0) (domains '((1 2 3))) (rows '((1) (2))))
        (let* ((program
                (relational-program
                 (relation x (value) (begin (set! calls (+ calls 1)) rows)
                           (domain (begin (set! calls (+ calls 1)) domains)))
                 (limits 8 8 16)))
               (reference (gerbil-ascent-program (list (relational-finite-source 'x 1 rows domains)) '() 8 8 16 '(x))))
          (check-equal? calls 2)
          (check-equal? (relational-query-name (relational-solve (relational-admit program)) 'x)
                        (relational-query-name (relational-solve (relational-admit reference)) 'x)))))
    (test-case "source updates and derived rows remain constrained by the declared domain"
      (let (session (relational-open-program-session (role-program '((1 2)))))
        (relational-program-session-run session)
        (check-exception (relational-program-append-source! session 'edge '(1 4)) true)
        (check-exception (relational-program-replace-source! session 'edge '((1 4))) true)
        (check-equal? (relational-program-query (relational-program-session-run session) 'reach) '((1 2))))
      (let (program
             (relational-program
              (relation x (n) '((1)) (role input))
              (relation y (n) '() (role derived) (domain '((1))))
              (rule (y ?m) (x ?n) (compute ?m (+ ?n 1)))
              (limits 8 8 16)))
        (check-exception (relational-solve (relational-admit program)) true)))
    (test-case "lattice annotations preserve checked join and domain constraints"
      (let (program
             (relational-program
              (relation values (n) '((1) (2)) (role input))
              (lattice best (n) '() max (role derived) (domain '((1 2))))
              (rule (best ?n) (values ?n))
              (limits 8 8 16)))
        (check-equal? (.ref program 'source-handles) '(values))
        (check-equal? (relational-query-name (relational-solve (relational-admit program)) 'best) '((2)))))
    (test-case "an explicit false domain cannot silently erase a constraint"
      (check-exception
       (relational-program (relation x (n) '((1)) (domain #f)) (limits 8 8 16)) true))
    (test-case "input-only rule heads reject with typed path and original reader location"
      (let* ((program
              (relational-program
               (relation seed (n) '((1)))
               (relation input (n) '() (role input))
               (rule (input ?n) (seed ?n))
               (limits 8 8 16)))
             (report (relational-admit/report program))
             (diagnostic (relational-admission-report-diagnostic report)))
        (check-equal? (relational-admission-report-admission report) #f)
        (check-equal? (relational-diagnostic-code diagnostic) 'input-rule-head)
        (check-equal? (relational-diagnostic-path diagnostic) '(rule 0 head 0))
        (check-equal? (vector? (relational-diagnostic-origin diagnostic)) #t)
        (check-exception (relational-open-program-session program) true)))
    (test-case "composition rechecks imported input roles rather than trusting fragments alone"
      (let* ((base (relational-fragment (import)
                    (source (x (n) '((1)) (role input))) (private) (export (x x))))
             (x (relational-export base 'x))
             (writer (relational-fragment (import (x x))
                      (source (seed (n) '((2)))) (private) (export)
                      (rule (x ?n) (seed ?n))))
             (report (relational-admit/report (relational-compose (list base writer) 8 8 16))))
        (check-equal? (relational-admission-report-admission report) #f)
        (check-equal? (relational-diagnostic-code (relational-admission-report-diagnostic report)) 'input-rule-head)))
    (test-case "origin metadata cannot retain or execute a caller callback"
      (let* ((called #f) (program (role-program '()))
             (rule (car (.ref program 'rules)))
             (foreign (.o (:: @ rule) source-origin: (lambda () (set! called #t))))
             (forged (.o (:: @ program) rules: (cons foreign (cdr (.ref program 'rules)))))
             (report (relational-admit/report forged)))
        (check-equal? called #f)
        (check-equal? (relational-admission-report-admission report) #f)
        (check-equal? (relational-diagnostic-code (relational-admission-report-diagnostic report)) 'invalid-rule-origin)))
    (test-case "cyclic origin lists reject before metadata traversal"
      (let* ((cycle (list #f)) (program (role-program '()))
             (rule (car (.ref program 'rules))))
        (set-cdr! cycle cycle)
        (let* ((foreign (.o (:: @ rule) source-origin: (vector #f cycle)))
               (forged (.o (:: @ program) rules: (cons foreign (cdr (.ref program 'rules)))))
               (report (relational-admit/report forged)))
          (check-equal? (relational-diagnostic-code (relational-admission-report-diagnostic report)) 'invalid-rule-origin))))
    (test-case "forged handles and changed derived rows cannot cross checked admission"
      (let* ((program (role-program '()))
             (forged (.o (:: @ program) source-handles: '(edge reach)))
             (report (relational-admit/report forged)))
        (check-equal? (relational-diagnostic-code (relational-admission-report-diagnostic report)) 'derived-source-handle)
        (check-exception (relational-open-program-session forged) true))
      (check-exception
       (relational-program (relation x (n) '((1)) (role derived)) (limits 8 8 16)) true))
    (test-case "ordinary declarations retain their existing mixed behavior"
      (let* ((program (relational-program (relation x (n)) (limits 8 8 16)))
             (session (relational-open-program-session program)))
        (check-equal? (.ref program 'source-handles) '(x))
        (check-equal? (relational-program-query (relational-program-session-run session) 'x) '())
        (relational-program-append-source! session 'x '(1))
        (check-equal? (relational-program-query (relational-program-session-run session) 'x) '((1)))))))
