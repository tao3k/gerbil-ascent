;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/operator
 :gerbil-ascent/program/operator-change
 (prefix-in :gerbil-ascent/t/performance/delta-sets/reference old-)
 :gerbil-ascent/t/performance/delta-sets/fixture)
(export ascent-delta-sets-test)
(def (check-change transformer before added (limit 4096))
 (let* ((old (relational-op-measure (cut old-relational-op-delta-change transformer before added limit)))
        (new (relational-op-measure (cut relational-op-delta-change transformer before added limit)))
        (expected (call-with-values (cut relational-op-reference-change transformer before added limit) list)))
  (check-equal? (relational-op-measurement-result-values new) (relational-op-measurement-result-values old))
  (check-equal? (delta-same-set? (relational-op-measurement-result-values new) expected) #t)
  (check-equal? (relational-op-measurement-join-probes new) (relational-op-measurement-join-probes old))
  (check-equal? (relational-op-measurement-fix-body-evaluations new) (relational-op-measurement-fix-body-evaluations old))))
(def ascent-delta-sets-test
 (test-suite "Normalized insertion set flow"
  (test-case "all small insertions preserve order membership and probe counts"
   (let (transforms
    (list (relational-op-function 1 (lambda (p) (relational-op-project p '(0))))
          (relational-op-function 1 (lambda (p) (relational-op-project p '())))
          (relational-op-function 1 (lambda (p) (relational-op-select-eq p 0 1)))
          (relational-op-function 1 (lambda (p) (relational-op-flatmap p 1 '(((0) (a)) ((1) (a)) ((2) (b))))))
          (relational-op-function 1 (lambda (p) (relational-op-project (relational-op-join p p 0 0) '(0))))))
    (def (rows mask) (map list (filter (lambda (i) (not (zero? (bitwise-and mask (arithmetic-shift 1 i))))) '(0 1 2))))
    (for-each (lambda (before)
     (for-each (lambda (added)
      (for-each (lambda (t) (check-change t (rows before) (rows added))) transforms)) (iota 8))) (iota 8))))
  (test-case "nested fixed points capture a stable external insertion"
   (let (transform (relational-op-function 1 (lambda (input)
    (relational-op-fix 1 (lambda (outer)
     (relational-op-union input
      (relational-op-fix 1 (lambda (inner) (relational-op-union outer inner)))))))))
    (check-change transform '((a) (b) (a)) '((b) (c) (c)))
    (check-change transform [] [])
    (check-change transform '((a)) '((a)))))
  (test-case "recursive join advances through several frontiers"
   (let (transform (relational-op-function 2 (lambda (edge)
    (relational-op-fix 2 (lambda (path)
     (relational-op-union edge (relational-op-project (relational-op-join path edge 1 0) '(0 3))))))))
    (check-change transform '((0 1) (1 2) (2 3)) '((3 4) (4 5)))
    (check-change transform '((0 1) (1 2)) '((2 0)))))
  (test-case "hash membership preserves supported scalar equality"
   (let* ((transform (relational-op-function 1 (lambda (p) (relational-op-project p '(0)))))
          (before '((#f) (#\a) (x) (1)))
          (added '((#f) (#\a) (x) (1) (#t) (#\b))))
    (check-change transform before added)
    (check-equal? before '((#f) (#\a) (x) (1)))
    (check-equal? added '((#f) (#\a) (x) (1) (#t) (#\b)))))
  (test-case "empty and singleton shortcuts still reject bounded overflow"
   (let (transform (relational-op-function 1 (lambda (p) (relational-op-fix 1 (lambda (x) (relational-op-union p x))))))
    (for-each (lambda (call) (check-exception (call) (lambda (_) #t)))
     (list (cut relational-op-delta-change transform '((a) (b)) [] 1)
           (cut relational-op-delta-change transform [] '((a) (b)) 1)
           (cut relational-op-delta-change transform '((a)) '((b)) 1)))
    (check-change transform '((a)) '((a)) 1)))))
