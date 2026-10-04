;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/program/finite-arithmetic
                 relational-capped-product relational-capped-power)
        (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/higher-order
                 relational-relation-type relational-arrow-type relational-type=?
                 relational-type-height-expression relational-type-right
                 relational-typed-term-data relational-typed-term-inputs relational-typed-source
                 relational-typed-function relational-typed-apply relational-typed-union
                 relational-typed-join relational-typed-project relational-typed-flatmap
                 relational-typed-select-eq
                 relational-typed-fix relational-typed-compile)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-admit relational-solve relational-query-name
                 relational-open-program-session relational-program-append-source!
                 relational-program-replace-source! relational-program-session-run relational-program-query)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-scalar? relational-copy-rows relational-finite-source relational-finite-lattice)
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

;;; Exhaustive finite truth data, independent of the compiler/type formulas.
(def (truth-tuples atoms arity)
  (if (zero? arity) '(())
    (foldr append []
           (map (lambda (atom)
                  (map (lambda (tail) (cons atom tail)) (truth-tuples atoms (- arity 1)))) atoms))))
(def (truth-subsets rows)
  (if (null? rows) '(())
    (let (tail (truth-subsets (cdr rows)))
      (append tail (map (lambda (subset) (cons (car rows) subset)) tail)))))
(def (truth-power base exponent)
  (if (zero? exponent) 1 (* base (truth-power base (- exponent 1)))))
(def (height-expression-value expression)
  (if (number? expression) expression
    (let ((left (height-expression-value (cadr expression)))
          (right (height-expression-value (caddr expression))))
      (case (car expression)
        ((expt) (truth-power left right))
        ((*) (* left right))
        (else (error "unexpected height expression"))))))

(def scheme-higher-order-test
  (test-suite "Finite positive higher-order descriptors"
    (test-case "scalar tags and duplicate domains preserve complete row membership"
      (let* ((atoms '(0 #f a #\a))
             (type (relational-relation-type 1 (append atoms atoms)))
             (rows (map list atoms)))
        (check-equal? (length (relational-type-right type)) 4)
        (check-equal? (relational-type=? type (relational-relation-type 1 (reverse atoms))) #t)
        (check-rows (solve (relational-typed-source 'tagged type (append rows rows))) rows)
        (check-equal? (height-expression-value (relational-type-height-expression type)) 4)))
    (test-case "checked atoms reject inexact mutable and opaque values"
      (for-each
       (lambda (atom)
         (check-equal? (relational-scalar? atom) #f)
         (check-exception (relational-relation-type 1 (list atom)) true)
         (check-exception (relational-copy-rows (list (list atom)) 1) true))
       (list 0.0 1/2 "a" (vector 'a) (cons 'a 'b) (lambda () 'a))))
    (test-case "same printed fresh symbols remain distinct domain inhabitants"
      (let* ((left (string->uninterned-symbol "same"))
             (right (string->uninterned-symbol "same"))
             (type (relational-relation-type 1 (list left right left)))
             (rows (list (list left) (list right))))
        (check-equal? (equal? left right) #f)
        (check-equal? (length (relational-type-right type)) 2)
        (check-rows (solve (relational-typed-source 'fresh type rows)) rows)))
    (test-case "empty domain distinguishes false from the true nullary relation"
      (let* ((nullary (relational-relation-type 0 '()))
             (unary (relational-relation-type 1 '())))
        (for-each
         (lambda (rows)
           (check-rows (solve (relational-typed-source 'unit nullary rows))
                       (if (null? rows) '() '(()))))
         '(() (()) (() ())))
        (check-equal? (height-expression-value (relational-type-height-expression nullary)) 1)
        (check-equal? (height-expression-value (relational-type-height-expression unary)) 0)
        (check-exception (relational-typed-source 'invalid unary '((0))) true)
        (check-exception (relational-typed-source 'invalid nullary '((0))) true)))
    (test-case "typed set output retains source occurrences and charges materialization"
      (let* ((type (relational-relation-type 1 '(0)))
             (term (relational-typed-source 'occurrences type '((0) (0)))))
        (let-values (((program output) (relational-typed-compile term 2 1 3)))
          (let (result (relational-solve (relational-admit program)))
            (check-equal? (eq? output 'occurrences) #f)
            (check-equal? (relational-query-name result 'occurrences) '((0) (0)))
            (check-rows (relational-query-name result output) '((0)))))
        (let-values (((program output) (relational-typed-compile term 1 1 3)))
          (check-exception (relational-solve (relational-admit program)) true))
        (let-values (((program output) (relational-typed-compile term 2 1 2)))
          (check-exception (relational-solve (relational-admit program)) true))))
    (test-case "typed retained updates preserve source authority set output and frozen results"
      (let-values (((program output)
                    (relational-typed-compile
                     (relational-typed-source 'editable (relational-relation-type 1 '(0 1)) '((0) (0)))
                     32 256 512)))
        (let* ((session (relational-open-program-session program))
               (initial (relational-program-session-run session)))
          (check-rows (relational-program-query initial output) '((0)))
          (check-exception (relational-program-append-source! session output '(0)) true)
          (check-exception (relational-program-replace-source! session output '()) true)
          (relational-program-append-source! session 'editable '(1))
          (check-rows (relational-program-query (relational-program-session-run session) output) '((0) (1)))
          (relational-program-replace-source! session 'editable '((1) (1)))
          (let (result (relational-program-session-run session))
            (check-rows (relational-program-query result output) '((1)))
            (check-equal? (relational-program-query result 'editable) '((1) (1))))
          (check-rows (relational-program-query initial output) '((0))))))
    (test-case "finite height formulas match exhaustive tiny tuple and relation universes"
      (for-each
       (lambda (atoms)
         (for-each
          (lambda (arity)
            (let* ((type (relational-relation-type arity atoms))
                   (tuples (truth-tuples atoms arity))
                   (relations (truth-subsets tuples))
                   (arrow (relational-arrow-type type type)))
              (check-equal? (height-expression-value (relational-type-height-expression type)) (length tuples))
              (check-equal? (height-expression-value (relational-type-height-expression arrow))
                            (* (length relations) (length tuples)))
              (displayln "FINITE-SIGNATURE-CHECKED " (length atoms) "/" arity) (force-output)))
          '(0 1 2)))
       '(() (0) (0 1))))
    (test-case "shared type graphs analyze without expanding repeated subgraphs"
      (let loop ((depth 24) (type (relational-relation-type 1 '(0))))
        (if (zero? depth)
          (let (height (relational-type-height-expression type))
            (check-equal? (car height) '*))
          (loop (- depth 1) (relational-arrow-type type type)))))
    (test-case "height admission canonicalizes changed domains and rejects opaque and cyclic spines"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (domain (relational-type-right type)))
        (set-car! (cdr domain) 0)
        (check-equal? (height-expression-value (relational-type-height-expression type)) 1)
        (check-rows (solve (relational-typed-source 'deduplicated type '((0)))) '((0))))
      (let* ((type (relational-relation-type 1 '(0)))
             (source (relational-typed-source 'source type '((0)))))
        (set-car! (relational-type-right type) (lambda () 'opaque))
        (check-exception (relational-type-height-expression type) true)
        (check-exception (relational-typed-compile source 32 256 512) true))
      (let* ((type (relational-relation-type 1 '(0)))
             (domain (relational-type-right type)))
        (set-cdr! domain domain)
        (check-exception (relational-type-height-expression type) true)))
    (test-case "typed admission rejects descriptor cycles and mutated mappings"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (source (relational-typed-source 'source type '((0))))
             (union (relational-typed-union source source)))
        (set-car! (relational-typed-term-inputs union) union)
        (check-exception (relational-typed-compile union 32 256 512) true))
      (let* ((type (relational-relation-type 1 '(0 1)))
             (source (relational-typed-source 'source type '((0))))
             (mapped (relational-typed-flatmap source type '(((0) (1))))))
        (set-car! (cdr (car (vector-ref (relational-typed-term-data mapped) 1))) 2)
        (check-exception (relational-typed-compile mapped 32 256 512) true)))
    (test-case "typed compilation owns admitted domains and source mapping rows"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (source (relational-typed-source 'owned type '((0))))
             (mapped (relational-typed-flatmap source type '(((0) (1))))))
        (let-values (((program output) (relational-typed-compile mapped 32 256 512)))
          (set-car! (relational-type-right type) 9)
          (set-car! (car (vector-ref (relational-typed-term-data source) 1)) 9)
          (set-car! (cdr (car (vector-ref (relational-typed-term-data mapped) 1))) 9)
          (check-rows (relational-query-name (relational-solve (relational-admit program)) output) '((1)))
          (check-exception (relational-typed-compile mapped 32 256 512) true))))
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
    (test-case "capped arithmetic equals independent exact natural calculations"
      (for-each
       (lambda (cap)
         (for-each
          (lambda (base)
            (for-each
             (lambda (exponent)
               (check-equal? (relational-capped-power cap base exponent)
                             (min cap (apply * (make-list exponent base))))
               (check-equal? (relational-capped-product cap base exponent)
                             (min cap (* base exponent))))
             (iota 17)))
          (iota 17)))
       (iota 17)))
    (test-case "capped arithmetic handles enormous exponents without materializing powers"
      (let (huge (apply * (make-list 100 10)))
        (check-equal? (relational-capped-power 0 0 0) 0)
        (check-equal? (relational-capped-power 1 0 huge) 0)
        (check-equal? (relational-capped-power 7 0 0) 1)
        (check-equal? (relational-capped-power 7 1 huge) 1)
        (check-equal? (relational-capped-power 7 2 huge) 7)
        (check-equal? (relational-capped-product 7 huge 0) 0)
        (check-equal? (relational-capped-product 7 huge huge) 7))
      (check-exception (relational-capped-power 4 2 -1) true)
      (check-exception (relational-capped-product 4 2 1.5) true))
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
