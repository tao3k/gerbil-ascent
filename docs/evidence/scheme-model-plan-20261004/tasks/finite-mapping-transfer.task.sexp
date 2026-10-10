(import :std/test :gerbil-ascent/program/higher-order :gerbil-ascent/program/scheme-language)
(define result (let* ((r (relational-relation-type 1 '(0 1 2 3 4))) (source (relational-typed-source 'input r '((2)))) (mapped (relational-typed-flatmap source r '(((2) (3)) ((2) (4))))) (solve (lambda (term) (let-values (((program output) (relational-typed-compile term 32 256 512))) (relational-query-name (relational-solve (relational-admit program)) output)))) (bits (lambda (rows) (foldl (lambda (row mask) (+ mask (expt 2 (car row)))) 0 rows)))) (bits (solve mapped))))
(check-equal? result '?)
