;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-admit relational-solve
                 relational-admit/report
                 relational-admission-report-admission
                 relational-admission-report-diagnostic
                 relational-diagnostic-code relational-diagnostic-path
                 relational-query-name relational-open-program-session
                 relational-program-replace-source!
                 relational-program-session-run relational-program-query))

(export scheme-native-language-test)

(def (filtered-program)
  (relational-program
   (relation edge (from to) '((1 2) (2 3) (3 4)))
   (relation blocked (from to) '((2 3)))
   (relation allowed (from to))
   (rule (allowed ?x ?y)
     (edge ?x ?y)
     (not (blocked ?x ?y)))
   (limits 16 16 32)))

(def scheme-native-language-test
  (test-suite "native Scheme captured values and stratified negation"
    (test-case "explicit value capture freezes a scalar at construction"
      (let ((calls 0) (selected 'gate))
        (let* ((program
                (relational-program
                 (relation tag (value) '((gate) (other)))
                 (relation chosen (value))
                 (rule (chosen (value (begin
                                        (set! calls (+ calls 1))
                                        selected)))
                   (tag (value selected)))
                 (limits 8 8 16)))
               (admission (relational-admit program)))
          (set! selected 'other)
          (check-equal? calls 1)
          (check-equal?
           (relational-query-name (relational-solve admission) 'chosen)
           '((gate))))))
    (test-case "mutable host capture is rejected"
      (check-exception
       (relational-program
        (relation source (value) '((1)))
        (relation output (value))
        (rule (output (value (vector 1))) (source 1))
        (limits 8 8 16)) true))
    (test-case "negative read uses completed lower stratum"
      (let (solution (relational-solve
                     (relational-admit (filtered-program))))
        (check-equal? (relational-query-name solution 'allowed)
                      '((1 2) (3 4)))))
    (test-case "negative source withdrawal recomputes without rewriting old result"
      (let* ((session (relational-open-program-session
                       (filtered-program)))
             (first (relational-program-session-run session)))
        (relational-program-replace-source!
         session 'blocked '((3 4)))
        (let (second (relational-program-session-run session))
          (check-equal? (relational-program-query first 'allowed)
                        '((1 2) (3 4)))
          (check-equal? (relational-program-query second 'allowed)
                        '((1 2) (2 3))))))
    (test-case "a negative cycle is rejected after whole-program composition"
      (let (program
            (relational-program
             (relation seed (value) '((1)))
             (relation a (value))
             (relation b (value))
             (rule (a ?x) (seed ?x) (not (b ?x)))
             (rule (b ?x) (seed ?x) (not (a ?x)))
             (limits 8 16 32)))
        (check-exception (relational-admit program) true)
        (let (diagnostic
              (relational-admission-report-diagnostic
               (relational-admit/report program)))
          (check-equal? (relational-diagnostic-code diagnostic)
                        'invalid-dependencies)
          (check-equal? (relational-diagnostic-path diagnostic)
                        '(program dependencies)))))
    (test-case "planner reports the actual failing body and head locations"
      (let* ((body-report
              (relational-admit/report
               (relational-program
                (relation edge (from to) '((1 2)))
                (relation path (from to))
                (rule (path ?x ?y)
                  (edge ?x ?y)
                  (missing ?y ?x))
                (limits 8 8 16))))
             (head-report
              (relational-admit/report
               (relational-program
                (relation edge (from to) '((1 2)))
                (relation path (from to))
                (rule (path ?x ?z) (edge ?x ?y))
                (limits 8 8 16)))))
        (check-equal? (relational-admission-report-admission body-report)
                      #f)
        (check-equal?
         (relational-diagnostic-code
          (relational-admission-report-diagnostic body-report))
         'invalid-body)
        (check-equal?
         (relational-diagnostic-path
          (relational-admission-report-diagnostic body-report))
         '(rule 0 body 1))
        (check-equal?
         (relational-diagnostic-code
          (relational-admission-report-diagnostic head-report))
         'invalid-head)
        (check-equal?
         (relational-diagnostic-path
          (relational-admission-report-diagnostic head-report))
         '(rule 0 head 0))))
    (test-case "successful report carries the admitted program"
      (let (report (relational-admit/report (filtered-program)))
        (check-equal? (relational-admission-report-diagnostic report) #f)
        (check-equal?
         (relational-query-name
          (relational-solve
           (relational-admission-report-admission report))
          'allowed)
         '((1 2) (3 4)))))))
