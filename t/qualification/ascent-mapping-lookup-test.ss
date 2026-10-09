;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/operator
 :gerbil-ascent/program/operator-change
 (prefix-in :gerbil-ascent/t/performance/mapping-lookup/reference old-)
 :gerbil-ascent/t/performance/mapping-lookup/fixture)
(export ascent-mapping-lookup-test)
(def (check-mapping transformer before added (limit 4096))
 (let* ((old (relational-op-measure (cut old-relational-op-delta-change transformer before added limit)))
        (new (relational-op-measure (cut relational-op-delta-change transformer before added limit)))
        (truth (call-with-values (cut relational-op-reference-change transformer before added limit) list)))
  (check-equal? (relational-op-measurement-result-values new) (relational-op-measurement-result-values old))
  (check-equal? (mapping-same-set? (relational-op-measurement-result-values new) truth) #t)
  (check-equal? (relational-op-measurement-join-probes new) (relational-op-measurement-join-probes old))
  (check-equal? (relational-op-measurement-fix-body-evaluations new) (relational-op-measurement-fix-body-evaluations old))))
(def (subset mask)
 (map list (filter (lambda (i) (not (zero? (bitwise-and mask (arithmetic-shift 1 i))))) '(0 1 2))))
(def ascent-mapping-lookup-test
 (test-suite "Ordered finite mapping lookup"
  (test-case "all small changes preserve duplicate fanout and missing-key order"
   (let (transform (relational-op-function 1 (lambda (p)
    (relational-op-flatmap p 1 '(((0) (a)) ((1) (b)) ((0) (c)) ((0) (a)) ((1) (a)))))))
    (for-each (lambda (before)
     (for-each (lambda (added) (check-mapping transform (subset before) (subset added))) (iota 8))) (iota 8))))
  (test-case "multi-column keys and scalar values retain full row equality"
   (let (transform (relational-op-function 2 (lambda (p)
    (relational-op-flatmap p 2 '(((#f #\a) (x 1)) ((#t #\a) (x 2)) ((#f #\a) (y 3)) ((#f #\b) (z 4)))))))
    (check-mapping transform '((#f #\a) (#t #\a)) '((#f #\b) (#f #\a) (#t #\b)))))
  (test-case "zero-arity keys and outputs preserve set collapse"
   (check-mapping (relational-op-function 0 (lambda (p)
    (relational-op-flatmap p 1 '((() (a)) (() (b)) (() (a)))))) '(()) '(()))
   (check-mapping (relational-op-function 1 (lambda (p)
    (relational-op-flatmap p 0 '(((0) ()) ((1) ()))))) '((0) (1)) '((2))))
  (test-case "equal keys in distinct descriptors keep their own output tables"
   (let (transform (relational-op-function 1 (lambda (p)
    (relational-op-union
     (relational-op-flatmap p 1 '(((0) (a)) ((1) (b))))
     (relational-op-flatmap p 1 '(((0) (c)) ((1) (d))))))))
    (check-mapping transform '((0) (1)) '((2)))
    (check-mapping transform '((1)) '((0)))
    (check-mapping transform [] '((0) (1)))))
  (test-case "recursive singleton frontiers reuse admitted multi-row lookup"
   (let (input (mapping-input 8 'fix))
    (check-mapping (vector-ref input 0) (vector-ref input 1) (vector-ref input 2))))
  (test-case "caller entries and descriptor rows remain unchanged across invocations"
   (let* ((entries '(((0) (a)) ((1) (b)) ((0) (c)))) (node #f)
          (transform (relational-op-function 1 (lambda (p)
           (set! node (relational-op-flatmap p 1 entries)) node)))
          (snapshot (map (lambda (row) (map identity row)) (vector-ref (relational-op-data node) 1))))
    (check-mapping transform '((0) (1)) [])
    (check-mapping transform '((1)) '((0)))
    (check-equal? entries '(((0) (a)) ((1) (b)) ((0) (c))))
    (check-equal? (vector-ref (relational-op-data node) 1) snapshot)))
  (test-case "fanout overflow still fails without returning a partial relation"
   (let (transform (relational-op-function 1 (lambda (p)
    (relational-op-flatmap p 1 '(((0) (a)) ((0) (b)) ((1) (c)))))))
    (for-each (lambda (procedure)
     (check-exception (procedure transform '((0) (1)) [] 2) (lambda (_) #t)))
     (list old-relational-op-delta-change relational-op-delta-change))
    (check-mapping transform '((0)) [] 2)))))
