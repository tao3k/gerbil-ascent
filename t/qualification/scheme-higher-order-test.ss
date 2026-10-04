;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/higher-order
                 relational-relation-type relational-arrow-type relational-type=?
                 relational-type-height-expression relational-typed-source
                 relational-typed-function relational-typed-apply relational-typed-union
                 relational-typed-join relational-typed-project relational-typed-flatmap
                 relational-typed-select-eq
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
    (test-case "lexical lowering agrees with independent finite algebra on every input pair"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (subsets '(() ((0)) ((1)) ((0) (1))))
             (factory
              (relational-typed-function
               type (lambda (captured)
                      (relational-typed-function
                       type (lambda (argument)
                              (relational-typed-union
                               captured
                               (relational-typed-flatmap
                                (relational-typed-project
                                 (relational-typed-select-eq
                                  (relational-typed-join captured argument 0 0) 0 0)
                                 '(1))
                                type '(((0) (1)) ((1) (0)))))))))))
        (for-each
         (lambda (left)
           ;; Reuse one returned closure across every argument, preserving the
           ;; defining capture. Expected rows use a direct membership model,
           ;; not the typed/operator interpreter or the compiler under test.
           (let (closure (relational-typed-apply
                          factory (relational-typed-source 'left type left)))
             (for-each
              (lambda (right)
                (let* ((added? (and (member '(0) left) (member '(0) right)))
                       (expected (if (and added? (not (member '(1) left)))
                                   (cons '(1) left) left)))
                  (check-rows
                   (solve (relational-typed-apply
                           closure (relational-typed-source 'right type right))) expected)))
              subsets))) subsets)))
    (test-case "normalization publishes the latest domain order without leaking between compiles"
      (let* ((input-type (relational-relation-type 1 '(a b)))
             (source (relational-typed-source 'source input-type '((a)))))
        (for-each
         (lambda (output-domain mapped expected)
           (let-values (((program output)
                         (relational-typed-compile
                          (relational-typed-flatmap
                           source (relational-relation-type 1 output-domain)
                           (list (list '(a) (list mapped)))) 32 256 512)))
             (let (relation (find (lambda (relation) (eq? (.ref relation 'name) output))
                                 (.ref program 'relations)))
               (check-equal? (vector-ref (.ref relation 'checked-domain) 1)
                             (list expected)))))
         '((b c) (z b) (b c)) '(c z c) '((c a b) (z a b) (c a b)))))
    (test-case "domain collection retains the exact normalization budget boundary"
      (let* ((type (relational-relation-type 1 '(#f #\x)))
             (source (relational-typed-source 'source type '((#f))))
             (term (relational-typed-flatmap source type '(((#f) (#\x))))))
        (check-equal?
         (with-catch error-message
           (lambda () (relational-typed-compile term 32 256 512 5) 'accepted))
         "typed normalization budget exceeded")
        (let-values (((program output) (relational-typed-compile term 32 256 512 6)))
          (check-equal? (symbol? output) #t)
          (check-equal? (pair? (.ref program 'relations)) #t))))
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
    (test-case "finite height arithmetic preserves empty and nullary function bottoms"
      (for-each
       (lambda (arity)
         (let* ((type (relational-relation-type arity '()))
                (arrow (relational-arrow-type type type))
                (fixed
                 (relational-typed-fix (relational-typed-function arrow values)))
                (argument (relational-typed-source 'empty type '())))
           (check-equal? (relational-type-height-expression type)
                         (list 'expt 0 arity))
           (check-rows (solve (relational-typed-apply fixed argument)) '())))
       '(0 1)))
    (test-case "enormous function height rejects at the finite expansion cap"
      (let* ((type (relational-relation-type 128 '(0 1)))
             (arrow (relational-arrow-type type type))
             (fixed
              (relational-typed-fix (relational-typed-function arrow values)))
             (argument (relational-typed-source 'wide type '()))
             (applied (relational-typed-apply fixed argument)))
        (check-equal?
         (with-catch error-message
           (lambda () (relational-typed-compile applied 32 256 512 200) 'accepted))
         "typed function fixed-point height exceeds normalization budget")))
    (test-case "height expressions distinguish relation height and higher-order function space"
      (let (type (relational-relation-type 1 '(0 1)))
        (check-equal? (relational-type-height-expression type) '(expt 2 1))
        (check-equal? (relational-type-height-expression (relational-arrow-type type type))
                      '(* (expt 2 (expt 2 1)) (expt 2 1)))
        (let (arrow (relational-arrow-type type type))
          (check-equal?
           (relational-type-height-expression (relational-arrow-type arrow arrow))
           '(* (expt (expt 2 (expt 2 1)) (expt 2 (expt 2 1)))
               (* (expt 2 (expt 2 1)) (expt 2 1)))))))))
