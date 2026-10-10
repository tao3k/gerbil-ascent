;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :std/error Error-message Error-irritants)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation gerbil-ascent-program gerbil-ascent-fragment)
        (rename-in (only-in :gerbil-ascent/t/performance/declaration-names/reference gerbil-ascent-program gerbil-ascent-fragment)
          (gerbil-ascent-program old-program) (gerbil-ascent-fragment old-fragment))
        :gerbil-ascent/t/performance/declaration-names/fixture)
(export ascent-declaration-names-test)
(def (failure call)
  (with-catch (lambda (e) (list (Error-message e) (Error-irritants e)))
    (lambda () (call) 'accepted)))
(def (force-order old? handles)
  (let* ((events [])
         (relations
          (map (lambda (label)
                 (.o (:: @ (gerbil-ascent-relation label 1 '((0))))
                     (name (begin (set! events (cons label events)) label)))) '(a b c)))
         (verdict (failure (lambda ()
                    (if old? (old-program relations [] 32 32 32 handles)
                      (gerbil-ascent-program relations [] 32 32 32 handles))))))
    (list verdict (reverse events))))
(def ascent-declaration-names-test
  (test-suite "construction-owned declaration and export names"
    (test-case "ordered handles missing names and duplicate priority match the frozen constructor"
      (let (relations (map (lambda (name) (gerbil-ascent-relation name 1 [])) '(a b c)))
        (for-each
         (lambda (handles)
           (check-equal?
            (failure (lambda () (gerbil-ascent-program relations [] 32 32 32 handles)))
            (failure (lambda () (old-program relations [] 32 32 32 handles)))))
         '((a a missing) (missing a a) (c b a) (a 99 missing) (99 a) ()))
        (check-equal? (.ref (gerbil-ascent-program relations [] 32 32 32 '(c a b)) 'source-handles)
                      '(c a b))))
    (test-case "computed name first-force order agrees for success and every early failure"
      (for-each (lambda (handles)
                  (check-equal? (force-order #f handles) (force-order #t handles)))
                '((a) (c a b) (a a) (missing a) (99 a) ())))
    (test-case "export validation preserves first invalid association and resolver diagnostics"
      (let (relations (list (gerbil-ascent-relation 'a 1 [])))
        (for-each
         (lambda (exports)
           (check-equal?
            (failure (lambda () (gerbil-ascent-fragment relations [] exports '(a))))
            (failure (lambda () (old-fragment relations [] exports '(a))))))
         '(((x . a) (x . a) (99 . a)) ((99 . a) (x . a)) ((x . 99)) (99) ()))
        (let ((a (.ref (old-fragment relations [] '((x . a)) '(a)) 'exports))
              (b (.ref (gerbil-ascent-fragment relations [] '((x . a)) '(a)) 'exports)))
          (check-equal? (b 'x) 'a)
          (check-equal? (failure (cut b 'missing)) (failure (cut a 'missing))))))
    (test-case "caller mutations cannot rewrite exports or the copied source-handle cut"
      (let* ((relations (list (gerbil-ascent-relation 'a 1 [])))
             (entry (cons 'x 'a)) (exports (list entry)) (handles (list 'a))
             (fragment (gerbil-ascent-fragment relations [] exports handles))
             (resolve (.ref fragment 'exports)))
        (set-car! entry 'rewritten) (set-cdr! entry 'other) (set-car! handles 'other)
        (check-equal? (resolve 'x) 'a)
        (check-equal? (.ref fragment 'source-handles) '(a))
        (check-exception (resolve 'rewritten) true)))
    (test-case "a fresh construction observes refined relation names"
      (let* ((original (gerbil-ascent-relation 'a 1 []))
             (relations (list original))
             (held (gerbil-ascent-program relations [] 32 32 32 '(a))))
        (set-car! relations (.o (:: @ original) name: 'b))
        (check-exception (gerbil-ascent-program relations [] 32 32 32 '(a)) true)
        (check-equal? (.ref (gerbil-ascent-program relations [] 32 32 32 '(b)) 'source-handles) '(b))
        (check-equal? (.ref held 'source-handles) '(a))))
    (test-case "complete wide fragment program and native cold consumers retain ordered truth"
      (for-each
       (lambda (scenario)
         (let* ((a (names-prepare #t scenario)) (b (names-prepare #f scenario))
                (view (names-consume b scenario)))
           (check-equal? view (names-consume a scenario))
           (when (memq scenario '(fragment small empty))
             (check-equal? (cadr view) (map cdr (vector-ref b 3))))
           (when (eq? scenario 'cold)
             (check-equal? (cadr view) (make-list 64 '((0)))))
           (displayln "DECLARATION-NAMES-NATIVE " scenario) (force-output)))
       '(program fragment cold small empty)))))
