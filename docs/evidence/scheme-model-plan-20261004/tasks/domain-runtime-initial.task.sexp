(import :std/test :gerbil-ascent/program/higher-order :gerbil-ascent/program/scheme-language)
(define result (let-values (((program output) (relational-typed-compile (relational-typed-source 'input (relational-relation-type 1 '(0 1)) '((0))) 32 256 512))) (let (session (relational-open-program-session program)) (relational-program-session-run session) (with-catch (lambda (_error) 1) (lambda () (relational-program-append-source! session 'input '(2)) 0)))))
(check-equal? result '?)
