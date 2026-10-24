;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite test-case check-equal?)
        :gerbil-ascent/core/expression-plan
        (rename-in :gerbil-ascent/t/performance/callback-plan/expression-reference
          (gerbil-ascent-compile-frame-call old-call)
          (gerbil-ascent-compile-frame-sequence old-sequence)
          (gerbil-ascent-compile-input-guard old-guard)))
(export ascent-callback-plan-test)
(def (run-sequence compile mode)
  (let ((trace []) (frame (vector 1)))
    (def (record tag value) (set! trace (cons (list tag value) trace)) value)
    (let* ((actions (list
             (vector 'binding 0 (lambda (f) (record 'binding (+ (vector-ref f 0) 2))))
             (vector 'guard (lambda (f)
               (record 'guard (vector-ref f 0))
               (case mode ((raise) (error "planned callback failure"))
                          ((invalid) 3) ((reject) #f) (else #t))))
             (vector 'binding 0 (lambda (f) (record 'suffix (+ (vector-ref f 0) 7))))))
           (before (map vector->list actions))
           (call (compile actions)))
      (check-equal? trace [])
      (check-equal? (map vector->list actions) before)
      (let (result (with-catch (lambda (e) (error-message e)) (lambda () (call frame))))
        (list result (vector-ref frame 0) (reverse trace))))))
(def ascent-callback-plan-test
  (test-suite "Ordered callback plan construction and metadata lifetime"
    (test-case "ordered execution preserves effects failures and guard short circuit"
      (for-each
       (lambda (mode)
         (let ((a (run-sequence old-sequence mode))
               (b (run-sequence gerbil-ascent-compile-frame-sequence mode)))
           (check-equal? b a)
           (check-equal? (caddr b)
             (if (eq? mode 'accept) '((binding 3) (guard 3) (suffix 10))
                 '((binding 3) (guard 3))))))
       '(accept reject invalid raise)))
    (test-case "deep plans compile without execution and reusable frames remain independent"
      (let* ((calls 0)
             (actions (map (lambda (_) (vector 'binding 0
                       (lambda (frame) (set! calls (+ calls 1)) (+ (vector-ref frame 0) 1))))
                           (iota 8192)))
             (old (old-sequence actions))
             (new (gerbil-ascent-compile-frame-sequence actions)))
        (check-equal? calls 0)
        (let ((a (vector 0)) (b (vector 10)))
          (check-equal? (old a) #t)
          (check-equal? (new b) #t)
          (check-equal? (vector-ref a 0) 8192)
          (check-equal? (vector-ref b 0) 8202)
          (check-equal? (new b) #t)
          (check-equal? (vector-ref a 0) 8192)
          (check-equal? (vector-ref b 0) 16394))))
    (test-case "variadic guards match detached tuple semantics and reject shape changes"
      (for-each
       (lambda (size)
         (let* ((names (map (lambda (n) (string->symbol (string-append "v" (number->string n)))) (iota size)))
                (saved (map values names)) (a (old-guard names))
                (b (gerbil-ascent-compile-input-guard names)))
           (for-each (lambda (current) (check-equal? (b current) (a current)))
             (list names saved [] #f 1 (cons 'v0 'improper) (append names '(extra))
                   (if (pair? names) (cdr names) [])))
           (when (pair? names)
             (set-car! names 'changed)
             (check-equal? (b names) #f)
             (check-equal? (b saved) #t)
             (check-equal? (b (cons 'changed (cdr saved))) (a (cons 'changed (cdr saved)))))))
       '(0 1 2 3 32 256)))
    (test-case "direct calls preserve slot order repeated inputs and false values"
      (for-each
       (lambda (slots)
         (let* ((frame (vector 'first #f 'third 'fourth))
                (a (old-call list slots))
                (b (gerbil-ascent-compile-frame-call list slots)))
           (check-equal? (b frame) (a frame))
           (vector-set! frame 0 'updated)
           (check-equal? (b frame) (a frame))))
       '(() (1) (2 0) (2 1 2) (3 1 0 3) (3 2 1 0 3 2))))
    (test-case "direct calls remain reentrant and read arguments before callback mutation"
      (for-each
       (lambda (compile)
         (let* ((frame (vector 1 2 3 4)) (nested #f) (invoke #f))
           (set! invoke (compile
             (lambda (a b c d)
               (if nested (list a b c d)
                 (begin
                   (set! nested #t)
                   (vector-set! frame 0 99)
                   (let (inner (invoke (vector 10 20 30 40)))
                     (list (list a b c d) inner)))))
             '(0 1 2 3)))
           (check-equal? (invoke frame) '((1 2 3 4) (10 20 30 40)))))
       (list old-call gerbil-ascent-compile-frame-call)))
    (test-case "general metadata elements retain value equality"
      (let* ((names (list (string-copy "first") (string-copy "second") (string-copy "third")))
             (a (old-guard names)) (b (gerbil-ascent-compile-input-guard names))
             (copy (map string-copy names)))
        (check-equal? (b copy) (a copy))
        (check-equal? (b copy) #t)))))
