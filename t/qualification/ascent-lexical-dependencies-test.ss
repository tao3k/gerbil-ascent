;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/operator-descriptor :gerbil-ascent/program/operator-analysis
 :gerbil-ascent/t/performance/lexical-dependencies/fixture)
(export ascent-lexical-dependencies-test)
(def ascent-lexical-dependencies-test
 (test-suite "Ordered lexical dependency ownership"
  (test-case "nested bindings and shared DAGs preserve every node dependency order"
    (for-each (lambda (width)
     (for-each (lambda (shape)
       (let* ((input (lexical-input width 16 0 shape)) (truth (lexical-expected input)))
         (check-equal? (lexical-same-set? (lexical-workflow #t input) truth) #t)
         (check-equal? (lexical-equal? (lexical-workflow #f input) truth) #t))) '(shared unary))) '(0 1 2 8)))
  (test-case "distinct overlapping sets keep first occurrence order and child spines"
    (let ((p #f) (q #f) (left #f) (right #f) (body #f))
      (let* ((root (relational-op-fix 1 (lambda (a)
                (set! p a)
                (relational-op-fix 1 (lambda (b)
                  (set! q b)
                  (set! left (relational-op-union a b))
                  (set! right (relational-op-union b a))
                  (set! body (relational-op-union left right)) body)))))
             (cache (operator-analysis-free-cache (analyze-operator-graph root))))
        (check-equal? (lexical-equal? (list (hash-ref cache left)) (list (list p q))) #t)
        (check-equal? (lexical-equal? (list (hash-ref cache right)) (list (list q p))) #t)
        (check-equal? (lexical-equal? (list (hash-ref cache body)) (list (list p q))) #t)
        (check-equal? (hash-ref cache root) []))))
  (test-case "apply binds only its own parameter and escaped captures still reject"
    (let ((outside #f) (transform #f))
      (let (root (relational-op-fix 1 (lambda (p)
         (set! outside p)
         (set! transform (relational-op-function 1 (lambda (q) (relational-op-union q p))))
         (relational-op-apply transform (relational-op-source 'base 1 '((1)))))))
        (check-equal? (hash-ref (operator-analysis-free-cache (analyze-operator-graph root)) root) [])
        (check-exception (analyze-operator-graph (relational-op-apply transform (relational-op-source 'other 1 '((1))))) (lambda (_) #t))
        (check-exception (analyze-operator-graph outside) (lambda (_) #t)))))
  (test-case "separate admissions revalidate mutated descriptor metadata"
    (let* ((columns (list 0)) (root (relational-op-project (relational-op-source 'base 1 '((1))) columns)))
      (analyze-operator-graph root)
      (set-car! (relational-op-data root) 2)
      (check-exception (analyze-operator-graph root) (lambda (_) #t))))))
