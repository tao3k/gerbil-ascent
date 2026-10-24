;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/relation-view :std/test)
(export ascent-complete-key-test)
(def ascent-complete-key-test
  (test-suite "Complete-key admission and frozen tiny owners"
    (test-case "all canonical keys preserve stored values, order and duplicate owners"
      (for-each (lambda (prefix)
        (for-each (lambda (owners)
          (let* ((left (list #f 1 2)) (right (list 2 3 #f))
                 (blocks (make-list owners (make-rectangle prefix left right)))
                 (rows (apply append (map (lambda (_)
                   (apply append (map (lambda (a) (map (lambda (b) (append prefix (list a b))) right)) left))) blocks)))
                 (columns (iota (+ 2 (length prefix)))))
            (for-each (lambda (indexed?)
              (let (view (gerbil-ascent-rectangle-view blocks (length rows) (* owners 6) indexed?))
                (for-each (lambda (key)
                  (check-equal? (gerbil-ascent-view-rows view columns key)
                    (filter (lambda (row) (equal? row key)) rows)))
                  (append rows (list (append prefix '(absent 2))))))) '(#f #t)))) '(0 1 2 3)))
        '(() (#f) (scope 7))))
    (test-case "complete schema does not bypass malformed key admission"
      (let (view (gerbil-ascent-rectangle-view (list (make-rectangle '(g) '(1 2) '(2 3))) 4 4 #t))
        (for-each (lambda (selectors)
          (check-equal? (with-catch (lambda (_) #t)
            (lambda () (gerbil-ascent-view-rows view (car selectors) (cadr selectors)) #f)) #t))
          '(((0 1 2) (g 1)) ((0 1 2) (g 1 2 extra))
            ((0 -1 2) (g 1 2)) ((0 1 3) (g 1 2)) ((0 1.5 2) (g 1 2))
            ((0 1 1 3) (g 1 2 2))))))))
