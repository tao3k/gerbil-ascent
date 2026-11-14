;;; -*- Gerbil -*-
(import :std/test :gerbil-ascent/core/rule-bindings
 (prefix-in :gerbil-ascent/t/performance/term-matching/reference old-))
(export ascent-term-matching-test)
(def (outcome call)
 (with-catch (lambda (e) (list (error-message e) (error-irritants e))) call))
(def (mutation-pipeline bind)
 (let* ((row (list 0 1)) (terms (list #f (cons 'literal 2)))
        (payload (vector '(before) #f)))
  (vector-set! payload 1 (lambda (_)
   (set-cdr! row (list 2))
   (vector-set! payload 0 '(after))
   (list #f)))
  (set-car! terms (cons 'pattern payload))
  (bind terms row [])))
(def ascent-term-matching-test
 (test-suite "Structural term binding protocol"
  (test-case "all roles preserve ordered heads and false bindings"
   (let* ((terms (list '(wildcard) '(fresh-variable . x) '(variable . x)
                 '(literal . 2) (cons 'expression (vector '(x) identity))
                 (cons 'pattern (vector '(y z) identity))))
          (row (list 'ignored #f #f 2 #f '(3 4)))
          (scope '((prior . #f)))
          (next (gerbil-ascent-bind-row terms row scope)))
    (check-equal? next (old-gerbil-ascent-bind-row terms row scope))
    (check-equal? (eq? (list-tail next 3) scope) #t)
    (check-equal? (gerbil-ascent-head-row '((variable . z) (literal . 2) (variable . x)) next)
                  '(4 2 #f))))
  (test-case "callback mutation is observed at the continuation boundary"
   (check-equal? (mutation-pipeline gerbil-ascent-bind-row) '((after . #f)))
   (check-equal? (mutation-pipeline gerbil-ascent-bind-row)
                 (mutation-pipeline old-gerbil-ascent-bind-row)))
  (test-case "rejection skips later callbacks"
   (let* ((calls 0) (terms (list (cons 'pattern (vector '(x) (lambda (_) #f)))
                              (cons 'expression (vector [] (lambda () (set! calls (+ calls 1)) 0))))))
    (check-equal? (gerbil-ascent-bind-row terms '(0 0) []) #f)
    (check-equal? calls 0)
    (check-equal? (gerbil-ascent-bind-row '((variable . x) (variable . x)) '(#f 1) []) #f)))
  (test-case "head errors retain first diagnostic"
   (for-each (lambda (terms)
    (check-equal? (outcome (lambda () (gerbil-ascent-head-row terms [])))
                  (outcome (lambda () (old-gerbil-ascent-head-row terms [])))))
    '(((pattern) (variable . missing)) ((wildcard)) ((variable . missing)))))))
