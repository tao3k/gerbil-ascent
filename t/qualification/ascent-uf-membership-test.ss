;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view)
(export ascent-uf-membership-test)
(def ascent-uf-membership-test
  (test-suite "Frozen weighted owner membership and delta export"
    (test-case "indexed membership requires both endpoints in the same owner"
      (let* ((a (iota 32)) (b (map (cut + 100 <>) (iota 32)))
             (view (gerbil-ascent-rectangle-view
               (list (make-rectangle [] a a) (make-rectangle [] b b)) 2048 128 #t)))
        (for-each (lambda (row expected)
          (check-equal? (gerbil-ascent-view-contains? view row) expected))
          '((31 31) (131 131) (31 131) (131 31) (999 31) (31 31 31))
          '(#t #t #f #f #f #f))))
    (test-case "mixed schemas and false endpoint values retain exact membership"
      (let* ((members '(#f 0 1 2 3 4))
             (view (gerbil-ascent-rectangle-view
               (list (make-rectangle [] members members)
                     (make-rectangle '(scope) members members)) 72 12 #t)))
        (check-equal? (gerbil-ascent-view-contains? view '(#f 4)) #t)
        (check-equal? (gerbil-ascent-view-contains? view '(scope #f 4)) #t)
        (check-equal? (gerbil-ascent-view-contains? view '(other #f 4)) #f)))
    (test-case "difference export preserves order and fresh public rows"
      (let* ((axis (iota 16))
             (newer (gerbil-ascent-rectangle-view (list (make-rectangle '(7) axis axis)) 256 32 #t))
             (old-axis (iota 8))
             (older (gerbil-ascent-rectangle-view (list (make-rectangle '(7) old-axis old-axis)) 64 16 #t))
             (delta (gerbil-ascent-view-difference newer older 192))
             (expected (filter (lambda (row) (or (>= (cadr row) 8) (>= (caddr row) 8)))
                         (gerbil-ascent-view-rows newer))))
        (check-equal? (gerbil-ascent-view-rows delta) expected)
        (check-equal? (gerbil-ascent-view-rows delta '(1 2) '(15 15)) '((7 15 15)))
        (let (public (gerbil-ascent-view-rows delta))
          (set-car! (car public) 999)
          (check-equal? (gerbil-ascent-view-rows delta) expected))))
    (test-case "custom part carriers retain part probes instead of contains shortcuts"
      (let* ((newer (gerbil-ascent-rectangle-view (list (make-rectangle [] '(0 1) '(0 1))) 4 4 #t))
             (custom (make-relation-view #f #f 0 'total 1 1
                       (lambda (_columns _key consume) (consume '(0 0)))
                       (lambda (_) #f) #f
                       (lambda (columns key consume)
                         (when (andmap (lambda (_) (= _ 0)) key)
                           (consume [] 0 0)))))
             (delta (gerbil-ascent-view-difference newer custom 3)))
        (check-equal? (gerbil-ascent-view-rows delta) '((0 1) (1 0) (1 1)))))))
