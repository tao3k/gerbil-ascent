;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/list/list-builder :gerbil-ascent/core/relation-view)
(export ascent-uf-query-test)
(def (part-rows visit view columns key)
  (with-list-builder (emit!)
    (visit view columns key (lambda (prefix left right) (emit! (append prefix (list left right)))))))
(def (check-consumers view columns key)
  (let* ((full (gerbil-ascent-view-rows view))
         (expected (filter (lambda (row)
                     (andmap (lambda (column value) (equal? (list-ref row column) value)) columns key)) full)))
    (check-equal? (gerbil-ascent-view-rows view columns key) expected)
    (check-equal? (with-list-builder (emit!)
                    (gerbil-ascent-for-each-row emit! (gerbil-ascent-view-select view columns key))) expected)
    (for-each (lambda (visit) (check-equal? (part-rows visit view columns key) expected))
      (list gerbil-ascent-visit-view-parts! gerbil-ascent-visit-admitted-view-parts!))))
(def ascent-uf-query-test
  (test-suite "Invocation-owned grouped and composite UF queries"
    (test-case "frozen ordinal intersection skips unrelated owners and keeps stored values"
      (let* ((token (list 'token))
             (view (gerbil-ascent-rectangle-view
                    (map (lambda (group)
                           (let (axis (case group
                                        ((0 3 6) (list token #f 2))
                                        ((1 4) (list token 1))
                                        (else '(#f 2 3))))
                             (make-rectangle (list group) axis axis))) (iota 8))
                    62 44 #t)))
        (for-each (lambda (columns key) (check-consumers view columns key))
          '((1 2) (2 1 2 1) (0 1 2) (1 2 1) (1 2))
          (list (list (list 'token) 2) (list 2 (list 'token) 2 (list 'token))
                (list 3 (list 'token) 2) (list token 2 'missing) '(#f 2)))
        (check-exception (gerbil-ascent-view-rows view '(1 1 3) '(0 99 1)) exception?)
        (let (rows (gerbil-ascent-view-rows view '(1 2) (list (list 'token) 2)))
          (check-equal? (map car rows) '(0 3 6))
          (check (eq? (cadar rows) token) => #t)
          (gerbil-ascent-visit-view-parts! view '(1 2) (list token 2)
            (lambda (_prefix _left _right)
              (check-consumers view '(2 1) (list #f token)))))))
    (test-case "group scopes, condition order, repeats and false bindings share one contract"
      (for-each (lambda (indexed?)
        (let (view (gerbil-ascent-rectangle-view
                    (map (lambda (group)
                           (let (axis '(#f 0 1 2 3))
                             (make-rectangle (list group) (map values axis) (map values axis)))) '(0 7 9))
                    75 30 indexed?))
          (for-each (lambda (columns key) (check-consumers view columns key))
            '((0 1 2) (2 0 1 0 2) (1 2) (1 2 1) (0 0) (1 2 1) () (0 1))
            '((7 #f 2) (2 7 #f 7 2) (#f 2) (1 2 1) (7 9) (1 2 3) () (99 1)))))
        '(#t #f)))
    (test-case "mixed schemas and arbitrary prefixes keep checked fallback"
      (let (view (gerbil-ascent-rectangle-view
                  (list (make-rectangle [] '(0 1) '(2 3))
                        (make-rectangle '(scope label) '(0 1) '(2 3))) 8 8 #t))
        (for-each (lambda (columns key) (check-consumers view columns key))
          '((1 0 1) (0 0) ()) '((3 1 3) (missing missing) ()))
        ;; Mixed-width routing may select only the wider descriptors. A tiny
        ;; scan cannot force checked admission on an unrelated shorter row.
        (check-equal? (gerbil-ascent-view-rows view '(3) '(3))
          '((scope label 0 3) (scope label 1 3)))))
    (test-case "range admission is not bypassed by absent or conflicting constraints"
      (let (view (gerbil-ascent-rectangle-view (list (make-rectangle '(7) '(1 2) '(3 4))) 4 4 #t))
        (for-each (lambda (columns key)
                    (check-exception (gerbil-ascent-view-rows view columns key) exception?)
                    (check-exception (gerbil-ascent-visit-view-parts! view columns key void) exception?))
          '((0 3) (0 0 3) (-1) (0)) '((999 1) (7 9 1) (1) ()))))
    (test-case "nested query plans and public mutations do not affect the captured cut"
      (let* ((axis '(0 1 2))
             (view (gerbil-ascent-rectangle-view
                    (list (make-rectangle '(7) axis axis) (make-rectangle '(9) (map values axis) (map values axis))) 18 12 #t))
             (nested? #f)
             (actual (with-list-builder (emit!)
                       (gerbil-ascent-visit-view-parts! view '(0 1 1) '(7 1 1)
                         (lambda (prefix left right)
                           (unless nested? (set! nested? #t)
                             (check-consumers view '(2 0 2) '(2 9 2)))
                           (emit! (append prefix (list left right))))))))
        (check-equal? actual '((7 1 0) (7 1 1) (7 1 2)))
        (set-car! (car actual) 99)
        (check-consumers view '(0 1 2) '(7 1 2))))))
