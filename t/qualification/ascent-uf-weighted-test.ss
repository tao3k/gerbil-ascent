;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view :gerbil-ascent/table/trrel-uf
        :gerbil-ascent/t/performance/uf-weighted/fixture
        (prefix-in :gerbil-ascent/t/performance/uf-weighted/reference-relation-view old-))
(export ascent-uf-weighted-test)
(def (parts visit view columns key)
  (let (rows [])
    (visit view columns key (lambda (prefix left right)
      (set! rows (cons (append prefix (list left right)) rows))))
    (reverse! rows)))
(def ascent-uf-weighted-test
  (test-suite "Weighted UF owned export and single-axis binding"
    (test-case "complete weighted UF exports match previous complete answers"
      (for-each (lambda (scenario)
        (check-equal? (ui-consume (ui-prepare #f scenario) scenario #f)
                      (ui-expected (ui-prepare #t scenario) scenario)))
        '(heavy grouped left-query right-query dense sparse small)))
    (test-case "collector preserves descriptor order, duplicates and arbitrary prefixes"
      (for-each (lambda (prefix)
        (for-each (lambda (axes)
          (let* ((left (car axes)) (right (cadr axes))
                 (view (gerbil-ascent-rectangle-view (list
                   (make-rectangle prefix left right) (make-rectangle prefix '(9) '(8))) 0 0 #t))
                 (reference (old-gerbil-ascent-rectangle-view (list
                   (old-make-rectangle prefix left right) (old-make-rectangle prefix '(9) '(8))) 0 0 #t))
                 (expected (old-gerbil-ascent-view-rows reference)))
            (check-equal? (gerbil-ascent-view-rows view) expected)
            (let (public (gerbil-ascent-view-rows view))
              (set-car! (car public) 999) (set-cdr! public [])
              (check-equal? (gerbil-ascent-view-rows view) expected))))
          '((() ()) ((1 0 1) (3 2 3)) ((1 2) ()) (() (3 4)))))
        '(() (#f) (scope label #f))))
    (test-case "both bound axes preserve every checked and admitted protocol"
      (let* ((members '(0 1 2)) (rights '(3 4 5))
             (blocks (list (make-rectangle [] members rights)
                           (make-rectangle [] members '(6 7))))
             (view (gerbil-ascent-rectangle-view blocks 15 7 #t)))
        (for-each (lambda (column key expected)
          (check-equal? (capture-query view #f (list column) (list key)) expected)
          (for-each (lambda (visit)
            (check-equal? (parts visit view (list column) (list key)) expected))
            (list gerbil-ascent-visit-view-parts! gerbil-ascent-visit-admitted-view-parts!)))
          '(0 1 0 1) '(1 4 99 99)
          '(((1 3) (1 4) (1 5) (1 6) (1 7)) ((0 4) (1 4) (2 4)) () ()))
        (check-equal? (capture-query view #f '(0 0) '(1 2)) [])
        (check-equal? (capture-query view #f '(1 0) '(4 1)) '((1 4)))))
    (test-case "dense capture charges copied cells independently of old representation units"
      (let (state (gerbil-ascent-trrel-uf-state))
        (for-each (lambda (i) (gerbil-ascent-trrel-uf-count-insert! state (list i (+ i 1)) 1000000))
          (iota 256))
        (let (view (gerbil-ascent-trrel-uf-freeze state #f))
          (check-equal? (relation-view-count view) 33153)
          ;; 257 borrowed members + 33153 former rectangles + 225 compact
          ;; owners, each replacing k rectangles with k cells + one descriptor.
          (check-equal? (relation-view-units view) 33635))))
    (test-case "nested axis visitors keep independent fixed member selections"
      (let* ((view (gerbil-ascent-rectangle-view
                    (list (make-rectangle [] '(0 1 2) '(0 1 2))) 9 6 #t))
             (actual []) (nested? #f))
        (gerbil-ascent-visit-view-parts! view '(0) '(1)
          (lambda (_ left right)
            (unless nested? (set! nested? #t)
              (check-equal? (capture-query view #f '(1) '(2)) '((0 2) (1 2) (2 2))))
            (set! actual (cons (list left right) actual))))
        (check-equal? (reverse! actual) '((1 0) (1 1) (1 2)))))))
