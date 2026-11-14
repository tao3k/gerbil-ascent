;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view)
(export ascent-membership-routing-test)
(def ascent-membership-routing-test
 (test-suite "Frozen routed membership and delta ownership"
  (test-case "mixed arity and equal values in unrelated owners match full export"
   (let* ((blocks (list (make-rectangle [] '(#f (x)) '(1 2))
                        (make-rectangle '(#f) '(a b) '(3 4))
                        (make-rectangle '(other) '(c a) '(5 6))
                        (make-rectangle '(nested group) '(a) '(1))))
          (view (gerbil-ascent-rectangle-view blocks 13 4 #t))
          (scan (gerbil-ascent-rectangle-view blocks 13 4 #f))
          (rows (gerbil-ascent-view-rows scan)))
     (for-each (lambda (row)
       (check-equal? (gerbil-ascent-view-contains? view row) (and (member row rows) #t))
       (check-equal? (gerbil-ascent-view-contains? scan row) (and (member row rows) #t)))
       (append rows '(() (a) (#f (x) 1) (#f c 3) (other b 5) (nested group b 1)
                      (nested group a 1 extra) (#f a 5) ((x) 3))))
     (check-equal? (gerbil-ascent-view-rows view) rows)))
  (test-case "all coordinate combinations preserve membership across 96 grouped cuts"
   (let* ((blocks (map (lambda (n) (make-rectangle (list n) (list (modulo n 3)) (list (modulo n 5)))) (iota 96)))
          (view (gerbil-ascent-rectangle-view blocks 96 96 #t)))
     (for-each (lambda (n)
       (for-each (lambda (a)
         (for-each (lambda (b)
           (check-equal? (gerbil-ascent-view-contains? view (list n a b))
                         (and (< n 96) (= a (modulo n 3)) (= b (modulo n 5))))) (iota 6))) (iota 4))) (iota 97))))
  (test-case "difference contains and ordered visits agree with explicit set subtraction"
   (let* ((base (list (make-rectangle '(#f) '(a b) '(1 2))))
          (old (gerbil-ascent-rectangle-view base 4 1 #t))
          (new (gerbil-ascent-rectangle-view (append base (list (make-rectangle '(next) '(a c) '(1 3)))) 8 2 #t))
          (delta (gerbil-ascent-view-difference new old 4))
          (rows (gerbil-ascent-view-rows delta)))
     (check-equal? rows '((next a 1) (next a 3) (next c 1) (next c 3)))
     (for-each (lambda (row)
       (check-equal? (gerbil-ascent-view-contains? delta row) (and (member row rows) #t)))
       (append (gerbil-ascent-view-rows new) '((#f c 3) (next b 1) (missing a 1))))))
  (test-case "empty indexed and unindexed cuts report absent facts of every arity"
   (for-each (lambda (indexed?)
     (let (view (gerbil-ascent-rectangle-view [] 0 0 indexed?))
       (for-each (lambda (row) (check-equal? (gerbil-ascent-view-contains? view row) #f))
         '(() (a) (a b) (a b c) (a b c d))))) '(#t #f)))))
