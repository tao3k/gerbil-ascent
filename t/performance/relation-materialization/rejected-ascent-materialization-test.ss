;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .o .mix .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/table/expression
                 gerbil-ascent-table-expression-prototype
                 gerbil-ascent-relation-closure-bounded)
        (only-in :gerbil-ascent/t/qualification/ascent-materialization-reference
                 ascent-materialization-reference-prototype
                 ascent-materialization-reference-closure-bounded))
(export ascent-materialization-test)
(def (expression prototype source radix)
  (.mix prototype (.o (source-pairs source) (radix radix))))
(def (outcome call)
  (with-catch (lambda (e) (error-message e)) call))
(def (distances edges)
  ;; Independent Floyd-Warshall oracle, without reflexive zero-length paths.
  (let (matrix (make-vector 9 #f))
    (for-each (lambda (pair) (vector-set! matrix pair 1)) edges)
    (for-each
     (lambda (via)
       (for-each
        (lambda (from)
          (for-each
           (lambda (to)
             (let ((a (vector-ref matrix (+ (* from 3) via)))
                   (b (vector-ref matrix (+ (* via 3) to)))
                   (old (vector-ref matrix (+ (* from 3) to))))
               (when (and a b (or (not old) (< (+ a b) old)))
                 (vector-set! matrix (+ (* from 3) to) (+ a b)))))
           (iota 3))) (iota 3))) (iota 3))
    matrix))
(def ascent-materialization-test
  (test-suite "Complete persistent relation materialization"
    (poo-flow-test-case "all 512 graphs match independent composition closure and shortest distance"
      (for-each
       (lambda (mask)
         (let* ((edges (filter (lambda (pair) (not (zero? (bitwise-and mask (arithmetic-shift 1 pair))))) (iota 9)))
                (source (.call UIntTrieSet .<-list edges))
                (old (expression ascent-materialization-reference-prototype source 3))
                (new (expression gerbil-ascent-table-expression-prototype source 3))
                (matrix (distances edges))
                (closure (filter (lambda (pair) (vector-ref matrix pair)) (iota 9)))
                (two-hop
                 (filter
                  (lambda (pair)
                    (let ((from (quotient pair 3)) (to (modulo pair 3)))
                      (or (member pair edges)
                          (ormap (lambda (via)
                                   (and (member (+ (* from 3) via) edges)
                                        (member (+ (* via 3) to) edges))) (iota 3)))))
                  (iota 9))))
           (check-equal? (.ref new 'at-most-two-hop-pairs) two-hop)
           (check-equal? (.ref new 'closure-pairs) closure)
           (check-equal? (.ref new 'shortest-distance-pairs) closure)
           (for-each
            (lambda (pair)
              (check-equal? ((.ref new 'shortest-distance-of) pair) (vector-ref matrix pair)))
            (iota 9))
           (for-each
            (lambda (slot) (check-equal? (.ref new slot) (.ref old slot)))
            '(two-hop-pairs at-most-two-hop-pairs closure-pairs shortest-distance-pairs))))
       (iota 512)))
    (poo-flow-test-case "demanded snapshots remain independent after source withdrawal and replacement"
      (for-each
       (lambda (radix)
         (let* ((edges (list (+ radix 2) (+ (* radix 2) 3) (+ radix 4) (+ (* radix 4) 3)))
                (source (.call UIntTrieSet .<-list edges))
                (initial (expression gerbil-ascent-table-expression-prototype source radix))
                (before (.ref initial 'closure-pairs))
                (withdrawn (.mix (.o (source-pairs (.call UIntTrieSet .remove source (+ (* radix 4) 3)))) initial)))
           (.ref initial 'shortest-distance-pairs)
           (check-equal? (.ref withdrawn 'closure-pairs)
                         (.ref (expression ascent-materialization-reference-prototype
                                           (.ref withdrawn 'source-pairs) radix) 'closure-pairs))
           (check-equal? (.ref initial 'closure-pairs) before)
           (check-equal? (.ref initial 'at-most-two-hop-pairs) before)))
       '(8 513)))
    (poo-flow-test-case "public neighbor overrides retain ordered callback traces and external composition"
      (let* ((source (.call UIntTrieSet .<-list '(1 5 6)))
             (left (.call UIntTrieSet .<-list '(2 3)))
             (calls [])
             (override (.o (right-index
                             (lambda (node visit)
                               (set! calls (cons node calls))
                               (visit (modulo (+ node 1) 3)))))))
        (def (run prototype)
          (let (e (.mix override (expression prototype source 3)))
            (list (.ref e 'at-most-two-hop-pairs)
                  ((.ref e 'compose-left) left)
                  (.ref e 'closure-pairs)
                  (.ref e 'shortest-distance-pairs))))
        (let* ((old (run ascent-materialization-reference-prototype)) (old-calls calls))
          (set! calls [])
          (check-equal? (run gerbil-ascent-table-expression-prototype) old)
          (check-equal? calls old-calls))))
    (poo-flow-test-case "bounded closure retains exact failures across empty dense and sparse snapshots"
      (for-each
       (lambda (radix)
         (for-each
          (lambda (rows)
            (let (source (.call UIntTrieSet .<-list rows))
              (for-each
               (lambda (budget)
                 (check-equal?
                  (outcome (lambda () (.ref (gerbil-ascent-relation-closure-bounded source radix budget) 'pairs)))
                  (outcome (lambda () (.ref (ascent-materialization-reference-closure-bounded source radix budget) 'pairs)))))
               '(0 1 2 3 8))))
          (list [] (list 1) (list 1 (+ radix 2)))))
       '(3 513)))))
