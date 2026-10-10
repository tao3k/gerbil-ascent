;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .ref) :gerbil-ascent/program/operator-descriptor
 :gerbil-ascent/program/operator-lowering :gerbil-ascent/program/objects
 :gerbil-ascent/t/performance/binding-resolution/fixture)
(export ascent-binding-resolution-test)
(def ascent-binding-resolution-test
 (test-suite "Checked lexical binding resolution"
  (test-case "ordinary and fixed-point unions allocate one copy for a repeated handle"
   (let (source (relational-op-source 'base 1 '((1))))
     (for-each (lambda (root)
       (let* ((input (vector root [])) (old (binding-workflow #t input)) (new (binding-workflow #f input)))
         (check-equal? (length (cadr old)) 2)
         (check-equal? (length (cadr new)) 1)
         (check-equal? (length (car new)) (length (car old)))
         (check-equal? (binding-shape new) (binding-shape old))))
       (list (relational-op-union source source)
             (relational-op-fix 1 (lambda (p) (relational-op-union p p)))))))
  (test-case "equal-row distinct sources retain both rules and lazy constructor order"
   (let ((events [])
         (root (relational-op-fix 1 (lambda (p)
           (relational-op-union (relational-op-source 'left 1 '((1)))
                                (relational-op-source 'right 1 '((1))))))))
     (call-with-values (lambda ()
       (lower-operator-graph root #f
         (lambda (name arity rows)
           (set! events (cons (list 'relation (if (memq name '(left right)) name 'derived)) events))
           (gerbil-ascent-relation name arity rows))
         (lambda (heads body)
           (set! events (cons (list 'rule (.ref (car body) 'relation)) events))
           (gerbil-ascent-rule heads body)))) (lambda results (void)))
     (check-equal? (reverse events) '((relation derived) (relation left) (rule left) (relation right) (rule right)))))
  (test-case "nested cached graphs retain exact emitted relation and variable topology"
   (for-each (lambda (width)
    (for-each (lambda (shape)
     (let (input (binding-input width 12 0 shape))
       (check-equal? (binding-shape (binding-workflow #f input))
                     (binding-shape (binding-workflow #t input))))) '(shared unary))) '(0 1 2 8)))
  (test-case "the same transform receives distinct lexical relation instances"
   (let* ((transform (relational-op-function 1 (lambda (p) (relational-op-project p '(0)))))
          (root (relational-op-union
                  (relational-op-apply transform (relational-op-source 'left 1 '((1))))
                  (relational-op-apply transform (relational-op-source 'right 1 '((2))))))
          (input (vector root [])))
     (check-equal? (binding-shape (binding-workflow #f input))
                   (binding-shape (binding-workflow #t input)))))
  (test-case "escaped graph is rejected before constructor callbacks"
   (let ((escaped #f) (calls 0))
     (relational-op-fix 1 (lambda (p) (set! escaped (relational-op-project p '(0))) p))
     (check-exception
       (lower-operator-graph escaped #f (lambda args (set! calls (+ calls 1)) (apply gerbil-ascent-relation args))
         (lambda args (set! calls (+ calls 1)) (apply gerbil-ascent-rule args))) (lambda (_) #t))
     (check-equal? calls 0)))))
