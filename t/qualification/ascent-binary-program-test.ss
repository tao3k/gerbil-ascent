;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/core/binary-program
                 gerbil-ascent-binary-relation
                 gerbil-ascent-binary-copy-rule
                 gerbil-ascent-binary-filter-rule
                 gerbil-ascent-binary-join-rule
                 gerbil-ascent-evaluate-binary-program))

(export ascent-binary-program-test)

(def (relation name encoded)
  (gerbil-ascent-binary-relation name (.call UIntTrieSet .<-list encoded)))

(def (evaluate declarations clauses (limit 64) (input-limit 64)
               (output-limit 128))
  (gerbil-ascent-evaluate-binary-program
   (.o (radix 8) (relations declarations) (rules clauses)
       (max-input-facts input-limit) (max-derived-pairs limit)
       (max-output-pairs output-limit))))

(def (pairs result name)
  ((.ref result 'pair-list-of) name))

(def ascent-binary-program-test
  (test-suite "ASCENT positive binary rules in Scheme"
    (test-case "recursive copy and join match the existing cyclic closure"
      (let* ((declarations (list (relation 'edge '(10 19 28 34 11))
                                 (relation 'reach '())))
             (rules (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                          (gerbil-ascent-binary-join-rule
                           'reach 'reach 'edge)))
             (result (evaluate declarations rules)))
        (check-equal? (pairs result 'reach)
                      '(10 11 12 18 19 20 26 27 28 34 35 36))
        (check-equal?
         (.call UIntTrieSet .list<- ((.ref result 'pairs-of) 'reach))
         (pairs result 'reach))
        (check-equal? (.ref result 'evaluation-path) 'transitive-closure)
        (check-equal? (pairs result 'edge) '(10 11 19 28 34))
        (check-equal? (pairs (evaluate declarations (reverse rules)) 'reach)
                      (pairs result 'reach))
        (check-equal? (pairs (evaluate
                             (list (relation 'edge '(10 19 28 11))
                                   (relation 'reach '())) rules)
                            'reach)
                      '(10 11 12 19 20 28))
        (check-equal? (pairs result 'reach)
                      '(10 11 12 18 19 20 26 27 28 34 35 36))))
    (test-case "diamond and support withdrawal match the Rust pair fixtures"
      (let* ((rules (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                          (gerbil-ascent-binary-join-rule
                           'reach 'reach 'edge)))
             (first (evaluate
                     (list (relation 'edge '(10 19 12 35))
                           (relation 'reach '())) rules))
             (withdrawn (evaluate
                         (list (relation 'edge '(10 12 35))
                               (relation 'reach '())) rules))
             (fully-withdrawn (evaluate
                               (list (relation 'edge '(10 12))
                                     (relation 'reach '())) rules)))
        (check-equal? (pairs first 'reach) '(10 11 12 19 35))
        (check-equal? (pairs withdrawn 'reach) '(10 11 12 35))
        (check-equal? (pairs fully-withdrawn 'reach) '(10 12))
        (check-equal? (pairs first 'reach) '(10 11 12 19 35))))
    (test-case "seeded recursive head preserves source facts and rule order"
      (let* ((declarations (list (relation 'edge '(10 19))
                                 (relation 'reach '(12))))
             (rules (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                          (gerbil-ascent-binary-join-rule
                           'reach 'reach 'edge)))
             (result (evaluate declarations rules 3 3 6)))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)
        (check-equal? (pairs result 'reach) '(10 11 12 19))
        (check-equal? (pairs (evaluate declarations (reverse rules) 3 3 6)
                             'reach)
                      (pairs result 'reach))
        (check-exception (evaluate declarations rules 2 3 6) true)))
    (test-case "Ascent if-clause parity composes guarded facts with a join"
      (let* ((declarations
              (list (relation 'number '(9 18 27 36 45))
                    (relation 'edge '(19 37))
                    (relation 'even '()) (relation 'odd '())
                    (relation 'selected '())))
             (rules
              (list (gerbil-ascent-binary-filter-rule
                     'even 'number
                     (lambda (from _to) (= (modulo from 2) 0)))
                    (gerbil-ascent-binary-filter-rule
                     'odd 'number
                     (lambda (from _to) (= (modulo from 2) 1)))
                    (gerbil-ascent-binary-join-rule
                     'selected 'even 'edge)))
             (result (evaluate declarations rules 7 7 14)))
        (check-equal? (pairs result 'even) '(18 36))
        (check-equal? (pairs result 'odd) '(9 27 45))
        (check-equal? (pairs result 'selected) '(19 37))
        (check-equal? (pairs (evaluate declarations (reverse rules) 7 7 14)
                             'selected)
                      '(19 37))))
    (test-case "guarded selection feeds both a copy and a join"
      (let* ((result
              (evaluate
               (list (relation 'edge '(10 19 20 37 29))
                     (relation 'selected '())
                     (relation 'copied '())
                     (relation 'twohop '()))
               (list (gerbil-ascent-binary-filter-rule
                      'selected 'edge (lambda (from _to) (even? from)))
                     (gerbil-ascent-binary-copy-rule 'copied 'selected)
                     (gerbil-ascent-binary-join-rule
                      'twohop 'selected 'edge)))))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)
        (check-equal? (pairs result 'selected) '(19 20 37))
        (check-equal? (pairs result 'copied) '(19 20 37))
        (check-equal? (pairs result 'twohop) '(21))))
    (test-case "two changing join inputs and multiple heads"
      (let* ((result
              (evaluate
               (list (relation 'edge '(10 19 28))
                     (relation 'left '()) (relation 'right '())
                     (relation 'joined '()) (relation 'output '()))
               (list (gerbil-ascent-binary-copy-rule 'left 'edge)
                     (gerbil-ascent-binary-copy-rule 'right 'edge)
                     (gerbil-ascent-binary-join-rule
                      'joined 'left 'right)
                     (gerbil-ascent-binary-copy-rule 'output 'joined)))))
        (check-equal? (pairs result 'joined) '(11 20))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)
        (check-equal? (pairs result 'output) '(11 20))))
    (test-case "staged recursive closure uses the composable evaluator"
      (let* ((result
              (evaluate
               (list (relation 'edge '(10 19 12 35))
                     (relation 'staged '())
                     (relation 'reach '()))
               (list (gerbil-ascent-binary-copy-rule 'staged 'edge)
                     (gerbil-ascent-binary-copy-rule 'reach 'staged)
                     (gerbil-ascent-binary-join-rule
                      'reach 'reach 'edge)))))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)
        (check-equal? (pairs result 'reach) '(10 11 12 19 35))))
    (test-case "sparse radix retains the same binary join semantics"
      (let* ((edges (.call UIntTrieSet .<-list '(515 1029)))
             (result
              (gerbil-ascent-evaluate-binary-program
               (.o (radix 513)
                   (relations
                    (list (gerbil-ascent-binary-relation 'edge edges)
                          (relation 'reach '())))
                   (rules
                    (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                          (gerbil-ascent-binary-join-rule
                           'reach 'reach 'edge)))
                   (max-input-facts 8) (max-derived-pairs 8)
                   (max-output-pairs 8)))))
        (check-equal? (pairs result 'reach) '(515 516 1029))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)))
    (test-case "dense closure respects combined output budgets and source publication"
      (let* ((width 32)
             (edges (apply append (map (lambda (from)
                      (map (lambda (step) (+ (* from width) (modulo (+ from step) width)))
                           (iota 31 1))) (iota width))))
             (declarations (list (relation 'edge edges) (relation 'reach '())
                                 (relation 'other '(7 4))))
             (clauses (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                           (gerbil-ascent-binary-join-rule 'reach 'reach 'edge))))
        (def (run derived output)
          (gerbil-ascent-evaluate-binary-program
           (.o (radix width) (relations declarations) (rules clauses)
               (max-input-facts 994) (max-derived-pairs derived)
               (max-output-pairs output))))
        (let (result (run 1024 2018))
          (check-equal? (.ref result 'evaluation-path) 'transitive-closure)
          (check-equal? (pairs result 'reach) (iota 1024))
          (check-equal? (pairs result 'edge) (list-sort < edges))
          (check-equal? (pairs result 'other) '(4 7))
          (check-equal? (.call UIntTrieSet .list<- ((.ref result 'pairs-of) 'reach)) (iota 1024)))
        (check-exception (run 1023 2018) true)
        (check-exception (run 1024 2017) true)))
    (test-case "general initialization preserves observable guard order"
      (let* ((calls [])
             (clauses (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                           (gerbil-ascent-binary-join-rule 'reach 'reach 'edge)
                           (gerbil-ascent-binary-filter-rule 'selected 'reach
                            (lambda (from to) (set! calls (cons (list from to) calls)) #t))))
             (result (gerbil-ascent-evaluate-binary-program
                      (.o (radix 32)
                          (relations (list (relation 'edge '(1 34 67))
                                           (relation 'reach '(4))
                                           (relation 'selected '())))
                          (rules clauses) (max-input-facts 4)
                          (max-derived-pairs 32) (max-output-pairs 64)))))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)
        (check-equal? (pairs result 'reach) '(1 2 3 4 34 35 67))
        (check-equal? (pairs result 'selected) (pairs result 'reach))
        (check-equal? (reverse calls) '((0 4) (2 3) (1 2) (0 1) (1 3) (0 2) (0 3)))))
    (test-case "persistent set demands retain snapshots and observe public row edits"
      (for-each
       (lambda (general?)
         (let* ((source (relation 'edge '(10 19)))
                (clauses (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                               (gerbil-ascent-binary-join-rule 'reach 'reach 'edge)))
                (result (evaluate (list source (relation 'reach '()) (relation 'other '()) (relation 'leaf '(7)))
                         (if general? (cons (gerbil-ascent-binary-copy-rule 'other 'edge) clauses) clauses)))
                (get-set (.ref result 'pairs-of))
                (original (get-set 'reach)))
           (set-car! (pairs result 'leaf) 8)
           (check-equal? (.call UIntTrieSet .list<- (get-set 'leaf)) '(8))
           (check-equal? (eq? original (get-set 'reach)) #t)
           (check-equal? (.call UIntTrieSet .list<- original) '(10 11 19))
           (set-car! (pairs result 'edge) 12)
           (check-equal? (.call UIntTrieSet .list<- (get-set 'edge)) '(12 19))
           (check-equal? (.call UIntTrieSet .list<- (.ref source 'pairs)) '(10 19))
           (set-car! (pairs result 'reach) 12)
           (check-equal? (.call UIntTrieSet .list<- (get-set 'reach)) '(11 12 19))
           (check-equal? (.call UIntTrieSet .list<- original) '(10 11 19))
           (check-exception (get-set 'missing) true)))
       '(#f #t)))
    (test-case "a dormant indexed right becomes active after several rounds"
      (let* ((calls '())
             (result (evaluate
                      (list (relation 'seed '(10)) (relation 'left '(1))
                            (relation 'stage1 '()) (relation 'stage2 '())
                            (relation 'live '()) (relation 'out '()) (relation 'selected '()))
                      (list (gerbil-ascent-binary-copy-rule 'stage1 'seed)
                            (gerbil-ascent-binary-copy-rule 'stage2 'stage1)
                            (gerbil-ascent-binary-copy-rule 'live 'stage2)
                            (gerbil-ascent-binary-join-rule 'out 'left 'live)
                            (gerbil-ascent-binary-filter-rule 'selected 'out
                             (lambda (from to) (set! calls (cons (list from to) calls)) #t))))))
        (check-equal? (.ref result 'evaluation-path) 'semi-naive)
        (check-equal? (pairs result 'out) '(2))
        (check-equal? (pairs result 'selected) '(2))
        (check-equal? calls '((0 2)))
        (check-equal? (pairs result 'seed) '(10))))
    (test-case "filter callbacks complete the delta before a budget error"
      (let (calls '())
        (check-exception
         (evaluate (list (relation 'source '(1 2 3)) (relation 'out '()))
                   (list (gerbil-ascent-binary-filter-rule 'out 'source
                          (lambda (from to) (set! calls (cons (list from to) calls)) #t))) 1)
         true)
        (check-equal? calls '((0 1) (0 2) (0 3)))))
    (test-case "pending duplicates share admission across rules and heads"
      (let* ((declarations (list (relation 'source '(1 2 3)) (relation 'left '())
                                 (relation 'right '())))
             (clauses (list (gerbil-ascent-binary-copy-rule 'left 'source)
                            (gerbil-ascent-binary-copy-rule 'left 'source)
                            (gerbil-ascent-binary-copy-rule 'right 'source)
                            (gerbil-ascent-binary-copy-rule 'right 'left)
                            (gerbil-ascent-binary-copy-rule 'left 'right)))
             (result (evaluate declarations clauses 6 3 9)))
        (check-equal? (pairs result 'left) '(1 2 3))
        (check-equal? (pairs result 'right) '(1 2 3))
        (check-exception (evaluate declarations clauses 5 3 9) true)
        (check-exception (evaluate declarations clauses 6 3 8) true)))
    (test-case "dense admission crosses word and padded domain boundaries"
      (for-each
       (lambda (width)
         (let* ((rows (list 0 15 16 (- (* width width) 1)))
                (clauses (list (gerbil-ascent-binary-copy-rule 'out 'source)
                               (gerbil-ascent-binary-copy-rule 'out 'source)))
                (result (gerbil-ascent-evaluate-binary-program
                         (.o (radix width) (relations (list (relation 'source rows) (relation 'out '())))
                             (rules clauses) (max-input-facts 4)
                             (max-derived-pairs 4) (max-output-pairs 8)))))
           (check-equal? (pairs result 'out) rows)
           (check-equal? (.call UIntTrieSet .list<- ((.ref result 'pairs-of) 'out)) rows)))
       '(5 32 512 513)))
    (test-case "invalid declarations and pair budget fail"
      (check-exception
       (evaluate (list (relation 'edge '(10)) (relation 'edge '())) '()) true)
      (check-exception
       (evaluate (list (relation 'edge '(64))) '()) true)
      (check-exception
       (evaluate (list (relation 'edge '(10)))
                 (list (gerbil-ascent-binary-copy-rule 'missing 'edge))) true)
      (check-exception
       (gerbil-ascent-binary-filter-rule 'out 'edge #f) true)
      (check-exception
       (evaluate (list (relation 'edge '(10)) (relation 'out '()))
                 (list (.o (kind 'filter) (head 'out)
                           (left 'edge) (predicate #f)))) true)
      (check-exception
       (evaluate (list (relation 'edge '(10)) (relation 'out '()))
                 (list (gerbil-ascent-binary-filter-rule
                        'out 'edge (lambda (_from _to) 1)))) true)
      (check-exception
       (evaluate (list (relation 'edge '(10 19 28))
                       (relation 'reach '()))
                 (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                       (gerbil-ascent-binary-join-rule
                        'reach 'reach 'edge)) 5) true)
      (check-exception
       (evaluate (list (relation 'edge '(10 19 28))) '() 64 2) true)
      (check-exception
       (evaluate (list (relation 'edge '(10 19 28))) '() 64 64 2)
       true)
      (check-exception
       (evaluate (list (relation 'edge '(10 19 28))
                       (relation 'reach '()))
                 (list (gerbil-ascent-binary-copy-rule 'reach 'edge))
                 64 64 5)
       true))))
