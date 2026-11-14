;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view :gerbil-ascent/table/trrel-uf)
(export ascent-uf-lookup-test)
(def (expected rows columns key)
  (filter (lambda (row) (andmap (lambda (c k) (equal? (list-ref row c) k)) columns key)) rows))
(def ascent-uf-lookup-test
  (test-suite "Owned complete lookup results"
    (test-case "all selector shapes retain order through the direct collector"
      (for-each (lambda (indexed?)
        (let* ((view (gerbil-ascent-rectangle-view
                      (list (make-rectangle '(#f) '(0 1 2) '(2 3 4))
                            (make-rectangle '(7) '(0 1) '(2 3))) 13 0 indexed?))
               (full (gerbil-ascent-view-rows view)))
          (for-each (lambda (columns key)
            (let (wanted (expected full columns key))
              (check-equal? (gerbil-ascent-trrel-uf-view-lookup view columns key) wanted)
              (check-equal? (gerbil-ascent-view-rows view columns key) wanted)))
            '(() (0) (1) (2) (2 0) (1 1) (1 1) (2))
            '(() (#f) (0) (2) (2 #f) (0 0) (0 1) (999))))) '(#f #t)))
    (test-case "explicit empty lookup keeps visitor order when complete export differs"
      (let* ((base (gerbil-ascent-explicit-view '((0 0) (1 1)) 2))
             (view (gerbil-ascent-view-with-export base (lambda () '((1 1) (0 0))))))
        (check-equal? (gerbil-ascent-view-rows view) '((1 1) (0 0)))
        (check-equal? (gerbil-ascent-trrel-uf-view-lookup view [] []) '((0 0) (1 1)))
        (check-equal? (gerbil-ascent-view-rows view [] []) '((0 0) (1 1)))))
    (test-case "multiple self-component owners reuse plans with exact endpoint order"
      (let* ((first '(0 1 2)) (second (list 0 1 2))
             (view (gerbil-ascent-rectangle-view
                     (list (make-rectangle '(#f) first first)
                           (make-rectangle '(7) second second)) 18 0 #t))
             (full (gerbil-ascent-view-rows view)))
        (for-each (lambda (column)
          (let (wanted (expected full (list column) '(1)))
            (check-equal? (gerbil-ascent-trrel-uf-view-lookup view (list column) '(1)) wanted)
            (for-each (lambda (visit)
              (let (actual [])
                (visit view (list column) '(1) (lambda (prefix left right)
                  (set! actual (cons (append prefix (list left right)) actual))))
                (check-equal? (reverse! actual) wanted)))
              (list gerbil-ascent-visit-view-parts! gerbil-ascent-visit-admitted-view-parts!)))) '(1 2))))
    (test-case "union fallback and explicit rows return independent outer and tuple spines"
      (let* ((left (gerbil-ascent-explicit-view '((0 0) (0 1)) 2))
             (right (gerbil-ascent-explicit-view '((1 0)) 1))
             (view (gerbil-ascent-view-union left right))
             (first (gerbil-ascent-trrel-uf-view-lookup view [] []))
             (sibling (gerbil-ascent-trrel-uf-view-lookup view [] [])))
        (set-car! (car first) 99) (set-cdr! first [])
        (check-equal? sibling '((0 0) (0 1) (1 0)))
        (check-equal? (gerbil-ascent-view-rows view) sibling)
        (check-equal? (gerbil-ascent-view-rows view '(1) '(0)) '((0 0) (1 0)))))
    (test-case "rectangle selection stays independent of custom complete export"
      (let* ((base (gerbil-ascent-rectangle-view
                     (list (make-rectangle '(7) '(0 1) '(2 3))) 4 0 #t))
             (view (gerbil-ascent-view-with-export base (lambda () '((custom export)))))
             (first (gerbil-ascent-view-rows view '(1) '(0)))
             (sibling (gerbil-ascent-view-rows view '(1) '(0))))
        (check-equal? (gerbil-ascent-view-rows view) '((custom export)))
        (check-equal? first '((7 0 2) (7 0 3)))
        (set-car! (car first) 99) (set-cdr! first [])
        (check-equal? sibling '((7 0 2) (7 0 3)))
        (check-equal? (gerbil-ascent-view-rows view [] [])
          '((7 0 2) (7 0 3) (7 1 2) (7 1 3)))))
    (test-case "custom visitors preserve callback order and rejection leaves the cut stable"
      (let* ((calls 0)
             (view (make-relation-view #f #f 0 'total 2 2
                     (lambda (columns key consume)
                       (set! calls (+ calls 1))
                       (for-each (lambda (row) (when (or (null? columns) (equal? (car row) (car key)))
                         (consume (map values row)))) '((0 1) (1 2))))
                     (lambda (_) #f) #f #f)))
        (for-each (lambda (columns key)
          (check-exception (gerbil-ascent-trrel-uf-view-lookup view columns key) true))
          '((0 1) (-1) (x)) '((0) (0) (0)))
        (check-equal? calls 0)
        (check-equal? (gerbil-ascent-trrel-uf-view-lookup view '(0) '(1)) '((1 2)))
        (check-equal? calls 1)
        (check-equal? (gerbil-ascent-view-rows view) '((0 1) (1 2)))))))
