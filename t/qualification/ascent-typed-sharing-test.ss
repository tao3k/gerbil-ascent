;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :std/error Error-message)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :gerbil-ascent/program/types GerbilAscentProgramContract)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation)
        :gerbil-ascent/program/higher-order
        (rename-in (only-in :gerbil-ascent/t/performance/typed-sharing/reference
          relational-relation-type relational-typed-source relational-typed-union
          relational-typed-function relational-typed-apply relational-typed-compile)
          (relational-relation-type old-type) (relational-typed-source old-source)
          (relational-typed-union old-union) (relational-typed-function old-function)
          (relational-typed-apply old-apply) (relational-typed-compile old-compile))
        (only-in :gerbil-ascent/program/scheme-language relational-admit relational-solve relational-query-name)
        :gerbil-ascent/t/performance/typed-sharing/fixture)
(export ascent-typed-sharing-test)
(def (shared seed union depth)
  (if (zero? depth) seed
    (let (child (shared seed union (- depth 1))) (union child child))))
(def (verdict compile term budget)
  (with-catch Error-message
    (lambda () (let-values (((program output) (compile term 32 512 512 budget))) 'accepted))))
(def (escaped make-type source function apply-term union)
  (let* ((type (make-type 1 '(0 1))) (saved #f)
         (fn (function type (lambda (parameter)
                  (let (body (union parameter parameter)) (set! saved body) body))))
         (argument (source 'seed type '((0)))))
    ;; The left branch first admits the shared body under its binder. The
    ;; right branch revisits that exact body outside the binder's scope.
    (union (apply-term fn argument) saved)))
(def ascent-typed-sharing-test
  (test-suite "owned typed DAG reuse preserves occurrence admission"
    (test-case "complete root validation and ordinary constructor checks survive success and failure"
      (let (term (relational-typed-source 'seed (relational-relation-type 1 '(0)) '((0))))
        (let-values (((program output) (relational-typed-compile term 32 512 512)))
          (check-equal? (eq? (validate GerbilAscentProgramContract program) program) #t)
          (check-exception (gerbil-ascent-relation 99 1 '((0))) true))
        (check-exception (relational-typed-compile term 0 512 512) true)
        (check-exception (gerbil-ascent-relation 99 1 '((0))) true)))
    (test-case "every shared occurrence retains the exact baseline budget verdict"
      (let* ((a (shared (old-source 'seed (old-type 1 '(0 1)) '((0))) old-union 3))
             (b (shared (relational-typed-source 'seed (relational-relation-type 1 '(0 1)) '((0)))
                        relational-typed-union 3)))
        (for-each (lambda (budget)
                    (check-equal? (verdict relational-typed-compile b budget)
                                  (verdict old-compile a budget))) (iota 64 1))
        (check-equal? (verdict relational-typed-compile b 44) "typed normalization budget exceeded")
        (check-equal? (verdict relational-typed-compile b 45) 'accepted)))
    (test-case "a previously admitted shared body cannot escape its lexical binder"
      (check-equal?
       (verdict relational-typed-compile
         (escaped relational-relation-type relational-typed-source relational-typed-function
                  relational-typed-apply relational-typed-union) 1000)
       "typed parameter outside admitted lexical scope")
      (check-equal?
       (verdict old-compile (escaped old-type old-source old-function old-apply old-union) 1000)
       "typed parameter outside admitted lexical scope"))
    (test-case "shared source payloads are freshly checked while published programs remain owned"
      (let* ((type (relational-relation-type 1 '(0 1)))
             (seed (relational-typed-source 'seed type '((0))))
             (term (shared seed relational-typed-union 2)))
        (let-values (((program output) (relational-typed-compile term 32 512 512)))
          (set-car! (car (vector-ref (relational-typed-term-data seed) 1)) 99)
          (check-equal? (verdict relational-typed-compile term 1000)
                        "typed relation value outside declared domain")
          (check-equal? (relational-query-name (relational-solve (relational-admit program)) output) '((0)))
          (set-car! (car (vector-ref (relational-typed-term-data seed) 1)) 1)
          (let-values (((program output) (relational-typed-compile term 32 512 512)))
            (check-equal? (relational-query-name (relational-solve (relational-admit program)) output) '((1)))))))
    (test-case "wide shared source mapping and controls retain complete native set truth"
      (for-each
       (lambda (scenario)
         (let ((a (sharing-prepare #t scenario)) (b (sharing-prepare #f scenario)))
           (check-equal? (sharing-consume a scenario) (sharing-consume b scenario))
           (sharing-verify! a) (sharing-verify! b)
           (displayln "TYPED-SHARING-NATIVE " scenario) (force-output)))
       '(source mapping single small)))))
