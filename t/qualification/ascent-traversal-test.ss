;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/positive-plan :gerbil-ascent/core/relation-view
 (prefix-in :gerbil-ascent/t/performance/positive-traversal/reference old-))
(export ascent-traversal-test)
(def (traversal-trace old? mode callback? stop?)
 (let* ((events []) (terms '((variable . g) (variable . x) (variable . y)))
        (outputs (if callback?
          (append terms (list (cons 'expression (vector '(x) (lambda (x)
            (set! events (cons (list 'head x) events))
            (when (and stop? (= x 2)) (error "head boundary" x)) x))))) terms))
        (head (vector 'out outputs))
        (body (list (vector 'atom (vector 'input terms []))))
        (plan ((if old? old-gerbil-ascent-compile-positive-plan gerbil-ascent-compile-positive-plan)
               (list head head) body))
        (rows '((#f 1 1) (#f 1 3) (#f 2 1) (#f 2 3)))
        (frame (make-vector 3 'dirty)))
  (with-catch
   (lambda (e) (list (reverse events) (error-message e) (error-irritants e)))
   (lambda ()
    ((if old? old-gerbil-ascent-run-positive-plan! gerbil-ascent-run-positive-plan!)
      plan frame -1
      (lambda args (case mode
        ((view) (gerbil-ascent-explicit-view rows 4))
        ((rectangle) (gerbil-ascent-rectangle-view (list (make-rectangle '(#f) '(1 2) '(1 3))) 4 5))
        (else rows)))
      (lambda (h row)
        (set! events (cons (cons (vector-ref h 0) (map values row)) events))
        ;; Consumers own detached row spines; the next duplicate head is fresh.
        (set-car! row 'changed))
      (lambda () (set! events (cons 'candidate events)))
      (and (eq? mode 'direct)
        (lambda (_ frame delta keys consume)
          (for-each (lambda (row) (consume (list (car row)) (cadr row) (caddr row))) rows) #t)))
    (reverse events)))))
(def ascent-traversal-test
 (test-suite "Unified positive candidate continuation"
  (test-case "all row providers retain ordered detached duplicate heads"
   (for-each (lambda (mode)
    (check-equal? (traversal-trace #f mode #f #f)
                  (traversal-trace #t mode #f #f))
    (check-equal? (traversal-trace #f mode #f #f)
      '(candidate (out #f 1 1) (out #f 1 1)
        candidate (out #f 1 3) (out #f 1 3)
        candidate (out #f 2 1) (out #f 2 1)
        candidate (out #f 2 3) (out #f 2 3)))) '(rows view rectangle direct)))
  (test-case "head callbacks and first errors retain candidate ordering"
   (for-each (lambda (mode)
    (for-each (lambda (stop?)
     (check-equal? (traversal-trace #f mode #t stop?)
                   (traversal-trace #t mode #t stop?))) '(#f #t)))
    '(rows view rectangle direct)))
  (test-case "zero through eight output slots retain direct and fallback rows"
   (for-each (lambda (width)
    (let* ((terms (map (lambda (n) (cons 'variable (string->symbol (number->string n)))) (iota width)))
           (head (vector 'out terms)) (body (list (vector 'atom (vector 'input terms []))))
           (plan (gerbil-ascent-compile-positive-plan (list head) body))
           (rows (list (iota width))) (actual []))
     (gerbil-ascent-run-positive-plan! plan (make-vector width #f) -1
       (lambda args rows) (lambda (_ row) (set! actual (cons row actual))))
     (check-equal? actual rows))) (iota 9)))
  (test-case "legacy output records and zero-atom plans share emission"
   (for-each (lambda (outputs)
    (let* ((head (vector 'out '((literal . #f))))
           (new (gerbil-ascent-compile-positive-plan (list head) []))
           (old (old-gerbil-ascent-compile-positive-plan (list head) []))
           (a []) (b []))
     (when outputs
      (vector-set! new 0 (list (vector head '((literal . #f)))))
      (vector-set! old 0 (list (vector head '((literal . #f))))))
     (gerbil-ascent-run-positive-plan! new (vector) -1 void
       (lambda (_ row) (set! a (cons row a))))
     (old-gerbil-ascent-run-positive-plan! old (vector) -1 void
       (lambda (_ row) (set! b (cons row b))))
     (check-equal? a '((#f))) (check-equal? a b))) '(#f #t)))))
