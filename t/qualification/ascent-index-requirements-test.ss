;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/index :gerbil-ascent/table/provider
 :gerbil-ascent/t/performance/index-requirements/fixture)
(export ascent-index-requirements-test)
(def (rejected? call) (with-catch (lambda (_) #t) (lambda () (call) #f)))
(def ascent-index-requirements-test
 (test-suite "Index requirement ownership"
  (test-case "logical requirement registration does not evaluate expression terms"
   (let* ((calls 0) (input (requirement-input 16 1 40 'curried))
          (owner (vector-ref (requirement-owner #f input) 0)))
    (for-each (lambda (rule)
      (for-each (lambda (action)
        (let (atom (vector-ref action 0))
          (when (vector? atom)
            (vector-set! atom 1
              (list '(literal . #f) '(literal . a)
                    (cons 'expression (lambda (_) (set! calls (+ calls 1)) 0)))))))
        (vector-ref (vector-ref rule 0) 1))) (vector-ref input 0))
    (row-indexes-plan-positive-rules! owner (vector-ref input 0))
    (check-equal? calls 0)
    (check-equal? ((row-indexes-rows owner) (cadr (vector-ref input 4)) [] #f #f) (vector-ref input 3))
    (check-equal? calls 0)))
  (test-case "all adapters preserve all delta held roots across provider and size boundaries"
   (for-each (lambda (kind)
    (for-each (lambda (size)
     (for-each (lambda (lane)
      (let (input (requirement-input 64 4 size kind))
       (check-equal? (requirement-workflow #f input lane) (requirement-expected input))
       (check-equal? (requirement-workflow #t input lane) (requirement-expected input))))
      '(rules actions positive))) '(0 2 31 32 40))) '(canonical curried mixed)))
  (test-case "a failed traversal retains earlier admitted requirements"
   (let* ((input (requirement-input 1 1 40 'curried))
          (context (requirement-owner #f input)) (owner (vector-ref context 0))
          (atoms (vector-ref input 4)))
    ((row-indexes-plan-atoms! owner) atoms)
    (check-equal? (rejected? (lambda ()
      (row-indexes-plan-positive-rules! owner
        (append (vector-ref input 0) (list (vector #f [])))))) #t)
    (let ((left ((row-indexes-rows owner) (cadr atoms) [] #f #f))
          (right ((row-indexes-rows owner) (caddr atoms) [] #f #f)))
     (check-equal? left (vector-ref input 3))
     (check-equal? (eq? left right) #t))))
  (test-case "live cache rejects every metadata adapter before traversal"
   (for-each (lambda (kind)
    (let* ((input (requirement-input 1 1 40 kind)) (owner (vector-ref (requirement-owner #f input) 0)))
     (row-indexes-plan-positive-rules! owner (vector-ref input 0))
     ((row-indexes-rows owner) (cadr (vector-ref input 4)) [] #f #f)
     (for-each (lambda (call)
      (check-exception (call) (lambda (e) (equal? (error-message e) "cannot replan a live physical index"))))
      (list (lambda () ((row-indexes-plan-atoms! owner) []))
            (lambda () (row-indexes-plan-rules! owner []))
            (lambda () (row-indexes-plan-actions! owner []))
            (lambda () (row-indexes-plan-positive-rules! owner [])))))) '(canonical curried)))
  (test-case "empty owner rejects requirements through each adapter"
   (let* ((owner (gerbil-ascent-make-row-indexes '#(()) '#(()) '#(0) '#(0) '#(0) '#(0) '#(#f) #f))
          (input (requirement-input 1 1 0 'canonical)))
    (row-indexes-plan-rules! owner []) (row-indexes-plan-actions! owner []) (row-indexes-plan-positive-rules! owner [])
    (for-each (lambda (call)
     (check-exception (call) (lambda (e) (equal? (error-message e) "ASCENT empty index owner has lookup requirements"))))
     (list (lambda () (row-indexes-plan-rules! owner (vector-ref input 1)))
           (lambda () (row-indexes-plan-actions! owner (vector-ref (vector-ref (car (vector-ref input 0)) 0) 1)))
           (lambda () (row-indexes-plan-positive-rules! owner (vector-ref input 0)))))))))
