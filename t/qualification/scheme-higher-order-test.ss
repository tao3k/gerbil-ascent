;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/higher-order
                 relational-relation-type relational-arrow-type relational-type=?
                 relational-type-height-expression relational-typed-source
                 relational-typed-function relational-typed-apply relational-typed-union
                 relational-typed-join relational-typed-project relational-typed-flatmap
                 relational-typed-fix relational-typed-compile)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-admit relational-solve relational-query-name
                 relational-open-program-session relational-program-append-source!
                 relational-program-replace-source! relational-program-session-run relational-program-query)
        (only-in :gerbil-ascent/program/scheme-checked relational-finite-source relational-finite-lattice)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program)
        (only-in :clan/poo/object .o .ref))
(export scheme-higher-order-test)

(def r2 (relational-relation-type 2 '(0 1 2 3)))
(def rr (relational-arrow-type r2 r2))
(def (close-with step)
  (relational-typed-function
   r2 (lambda (seed)
        (relational-typed-fix
         (relational-typed-function
          r2 (lambda (path)
               (relational-typed-union seed (relational-typed-apply step path))))))))
(def closure-builder (relational-typed-function rr close-with))
(def (step-for edge)
  (relational-typed-function
   r2 (lambda (path)
        (relational-typed-project
         (relational-typed-join path edge 1 0) '(0 3)))))
(def (solve term)
  (let-values (((program output) (relational-typed-compile term 32 256 512)))
    (displayln "HIGHER-ORDER-COMPILED") (force-output)
    (let (rows (relational-query-name (relational-solve (relational-admit program)) output))
      (displayln "HIGHER-ORDER-SOLVED") (force-output)
      rows)))
(def (check-rows actual expected)
  (check-equal? (length actual) (length expected))
  (for-each (lambda (row) (check-equal? (and (member row actual) #t) #t)) expected))

(def (with-relations program relations)
  (gerbil-ascent-program relations (.ref program 'rules)
   (.ref program 'max-input-facts) (.ref program 'max-derived-facts)
   (.ref program 'max-output-facts) (.ref program 'source-handles)))

(def scheme-higher-order-test
  (test-suite "Finite positive higher-order descriptors"
    (test-case "a function accepts a function and returns a closure over a finite fix"
      (let* ((edge (relational-typed-source 'edge r2 '((1 2) (2 3))))
             (seed (relational-typed-source 'seed r2 '((0 1))))
             (function (relational-typed-apply closure-builder (step-for edge))))
        (check-rows (solve (relational-typed-apply function seed))
                    '((0 1) (0 2) (0 3)))))
    (test-case "one returned function can be instantiated twice without capture aliasing"
      (let* ((edge (relational-typed-source 'edge r2 '((1 2) (2 3))))
             (a (relational-typed-source 'a r2 '((0 1))))
             (b (relational-typed-source 'b r2 '((1 2))))
             (function (relational-typed-apply closure-builder (step-for edge))))
        (check-rows
         (solve (relational-typed-union (relational-typed-apply function a)
                                        (relational-typed-apply function b)))
         '((0 1) (0 2) (0 3) (1 2) (1 3)))))
    (test-case "application checks nested function input and result signatures"
      (let* ((r1 (relational-relation-type 1 '(0 1 2 3)))
             (wrong (relational-typed-function r1 values)))
        (check-exception (relational-typed-apply closure-builder wrong) true)
        (check-exception
         (relational-typed-apply closure-builder
                                 (relational-typed-source 'not-function r2 '((0 1)))) true)))
    (test-case "finite domains reject bad rows and mappings instead of clamping"
      (let* ((r1 (relational-relation-type 1 '(0 1)))
             (source (relational-typed-source 'x r1 '((0)))))
        (check-exception (relational-typed-source 'bad r1 '((2))) true)
        (check-exception (relational-typed-flatmap source r1 '(((0) (2)))) true)
        (check-rows (solve (relational-typed-flatmap source r1 '(((0) (1))))) '((1)))))
    (test-case "typed construction freezes caller-owned source and domain spines"
      (let* ((atoms (list 0 1)) (row (list 0))
             (type (relational-relation-type 1 atoms))
             (source (relational-typed-source 'frozen type (list row))))
        (set-car! atoms 99)
        (set-car! row 99)
        (check-rows (solve source) '((0)))
        (check-equal? (relational-type=? type (relational-relation-type 1 '(1 0))) #t)))
    (test-case "escaped parameters and opaque function results reject"
      (let (escaped #f)
        (relational-typed-function r2 (lambda (parameter) (set! escaped parameter) parameter))
        (check-exception (relational-typed-compile escaped 32 256 512) true))
      (check-exception
       (relational-typed-function r2 (lambda (_parameter) (lambda () 'hidden-read))) true))
    (test-case "function fixed points use finite height and expansion is bounded"
      (let* ((fixed (relational-typed-fix (relational-typed-function rr values)))
             (argument (relational-typed-source 'argument r2 '((0 1)))))
        (check-exception (relational-typed-compile
                         (relational-typed-apply fixed argument) 32 256 512) true))
      (let* ((source (relational-typed-source 'x r2 '((0 1))))
             (identity (relational-typed-function r2 values)))
        (check-exception
         (relational-typed-compile (relational-typed-apply identity source) 32 256 512 1) true)))
    (test-case "recursive functions propagate across changed arguments for every finite seed"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (arrow (relational-arrow-type type type))
             (builds 0)
             (fixed
              (relational-typed-fix
               (relational-typed-function
                arrow (lambda (self)
                        (set! builds (+ builds 1))
                        (relational-typed-function
                         type (lambda (seed)
                                (relational-typed-union
                                 seed
                                 (relational-typed-apply
                                  self (relational-typed-flatmap
                                        seed type '(((0) (1)) ((1) (0)))))))))))))
        ;; Independent finite two-node reachability, including the empty seed.
        (for-each
         (lambda (rows expected)
           (check-rows (solve (relational-typed-apply
                              fixed (relational-typed-source 'seed type rows))) expected))
         '(() ((0)) ((1)) ((0) (1)))
         '(() ((0) (1)) ((0) (1)) ((0) (1))))
        (check-equal? builds 1)))
    (test-case "nested returned functions use a pointwise bottom and preserve lexical inputs"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (arrow (relational-arrow-type type (relational-arrow-type type type)))
             (fixed
              (relational-typed-fix
               (relational-typed-function
                arrow (lambda (self)
                        (relational-typed-function
                         type (lambda (left)
                                (relational-typed-function
                                 type (lambda (right)
                                        (relational-typed-union
                                         left (relational-typed-apply
                                               (relational-typed-apply self right) left)))))))))))
        (check-rows
         (solve (relational-typed-apply
                 (relational-typed-apply fixed (relational-typed-source 'left type '((0))))
                 (relational-typed-source 'right type '((1))))) '((0) (1)))))
    (test-case "function fixed points accept higher-order inputs and the empty codomain"
      (let* ((type (relational-relation-type 1 '(0)))
             (arrow (relational-arrow-type type type))
             (input (relational-typed-function type values))
             (seed (relational-typed-source 'seed type '((0))))
             (fixed
              (relational-typed-fix
               (relational-typed-function
                (relational-arrow-type arrow type)
                (lambda (self)
                  (relational-typed-function
                   arrow (lambda (function)
                           (relational-typed-union
                            seed (relational-typed-apply
                                  function (relational-typed-apply self function))))))))))
        (check-rows (solve (relational-typed-apply fixed input)) '((0))))
      (let* ((empty (relational-relation-type 1 '()))
             (type (relational-relation-type 1 '(0 1)))
             (arrow (relational-arrow-type type empty))
             (fixed (relational-typed-fix (relational-typed-function arrow values))))
        (check-rows (solve (relational-typed-apply
                           fixed (relational-typed-source 'seed type '((0))))) '())))
    (test-case "compiler bottom sources retain their exact empty native domain"
      (let* ((empty (relational-relation-type 1 '()))
             (type (relational-relation-type 1 '(0 1)))
             (arrow (relational-arrow-type type empty))
             (fixed (relational-typed-fix (relational-typed-function arrow values))))
        (let-values (((program output)
                      (relational-typed-compile
                       (relational-typed-apply fixed (relational-typed-source 'seed type '((0))))
                       32 256 512)))
          (let ((session (relational-open-program-session program))
                (bottom (car (.ref program 'source-handles))))
            (relational-program-session-run session)
            (check-exception (relational-program-append-source! session bottom '(0)) true)
            (check-rows (relational-program-query (relational-program-session-run session) output) '())))))
    (test-case "typed native sessions retain finite domains through replacement and rollback"
      (let-values (((program output)
                    (relational-typed-compile
                     (relational-typed-source 'finite (relational-relation-type 1 '(0 1)) '((0)))
                     32 256 512)))
        (let (session (relational-open-program-session program))
          (relational-program-session-run session)
          (check-exception (relational-program-append-source! session 'finite '(2)) true)
          (relational-program-replace-source! session 'finite '((1)))
          (check-exception (relational-program-replace-source! session 'finite '((2))) true)
          (check-exception (relational-program-append-source! session 'finite '(2)) true)
          (check-rows (relational-program-query (relational-program-session-run session) output) '((1))))))
    (test-case "native derivations outside the declared domain raise instead of truncating"
      (let* ((program (relational-program
                       (relation x (n) '((0)))
                       (rule (x ?m) (x ?n) (compute ?m (+ ?n 1)))
                       (limits 32 256 512)))
             (bounded (with-relations program
                       (list (relational-finite-source 'x 1 '((0)) '((0 1 2)))))))
        (check-exception (relational-solve (relational-admit bounded)) true)))
    (test-case "admission reconstructs finite predicates and rejects forged domain data"
      (let* ((relation (relational-finite-source 'x 1 '((0)) '((0 1))))
             (rogue (.o (:: @ relation) field-predicates: (list (lambda (_) #t))))
             (program (gerbil-ascent-program (list rogue) [] 32 256 512 '(x)))
             (session (relational-open-program-session program)))
        (check-exception (relational-program-append-source! session 'x '(2)) true)
        (check-exception
         (relational-admit (with-relations program
                            (list (.o (:: @ relation) checked-domain: (vector 'opaque '()))))) true)
        (check-exception (relational-finite-lattice 'l 1 '((0)) 'max '((bad))) true)))
    (test-case "height expressions distinguish relation height and higher-order function space"
      (let (type (relational-relation-type 1 '(0 1)))
        (check-equal? (relational-type-height-expression type) '(expt 2 1))
        (check-equal? (relational-type-height-expression (relational-arrow-type type type))
                      '(* (expt 2 (expt 2 1)) (expt 2 1)))))))
