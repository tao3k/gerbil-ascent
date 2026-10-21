;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/candidate/checked-program reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/finite-evidence
                 candidate-finite-evidence candidate-verify-finite-evidence)
        (prefix-in :gerbil-ascent/t/performance/stratified-replay/reference-finite old-)
        :gerbil-ascent/t/performance/stratified-replay/fixture
        :gerbil-ascent/candidate/stratified-proof
        :gerbil-ascent/candidate/stratified-producer
        (prefix-in :gerbil-ascent/t/performance/stratified-replay/reference-proof old-)
        (prefix-in :gerbil-ascent/t/performance/stratified-replay/reference-producer old-)
        (only-in :gerbil-ascent/candidate/datum candidate-copy-pairs))
(export ascent-stratified-replay-test)
(def (verify state witness budget old?)
  (with (#(snapshot spec rows new-finite _ old-finite) state)
    ((if old? old-candidate-verify-stratified-proof candidate-verify-stratified-proof)
     snapshot spec 'digest 'complete rows (if old? old-finite new-finite) 1000000 witness budget)))
(def (produce state budget old?)
  (with (#(snapshot spec rows new-finite _ old-finite) state)
    (let-values (((status witness)
                  ((if old? old-candidate-produce-stratified-proof candidate-produce-stratified-proof)
                   snapshot spec 'digest 'complete rows (if old? old-finite new-finite) 1000000 budget)))
      (list status witness))))
(def (reduction-state sources atom operator expected)
  (let* ((snapshot (reasoning-source-snapshot 'reduction-scope 1 sources))
         (spec (make-reasoning-candidate '((total . 2)) []
                 (list (vector '(total ?r ?n)
                         (list '(root ?r) (list 'reduce '?n operator atom)) 7))
                 (vector '(total ?r ?n) 0) '(4096 4096 8192)))
         (finite (candidate-finite-evidence snapshot spec 'digest 'complete expected 1000000))
         (old-finite (old-candidate-finite-evidence snapshot spec 'digest 'complete expected 1000000)))
    (let-values (((status proof)
                  (old-candidate-produce-stratified-proof snapshot spec 'digest 'complete expected old-finite 1000000 1000000)))
      (check-equal? status 'complete)
      (vector snapshot spec expected finite proof old-finite))))
(def ascent-stratified-replay-test
  (test-suite "complete stratified expression replay"
    (test-case "closure membership retains the stricter ground symbol grammar"
      (for-each
       (lambda (term)
         (let* ((rows (list (list term)))
                (snapshot (reasoning-source-snapshot 'ground 1 (list (list 'root 1 rows))))
                (spec (make-reasoning-candidate [] [] [] (vector '(root ?row) 0) '(8 16 32)))
                (finite (candidate-finite-evidence snapshot spec 'digest 'complete rows 1000000))
                (old-finite (old-candidate-finite-evidence snapshot spec 'digest 'complete rows 1000000))
                (proof (list 'stratified-proof-v1 (list (list 'source 'root (car rows) 1 [])) '(0)))
                (state (vector snapshot spec rows finite proof old-finite)))
           (check-equal? (verify state proof 1000000 #f)
                         (if (memq term '(?x ?_)) 'invalid 'valid))
           (for-each (lambda (budget)
                       (check-equal? (verify state proof budget #f) (verify state proof budget #t)))
                     (iota 10 1))))
       '(#f a ? ?x ?_)))
    (test-case "reduction-local repeats literals wildcards and false outer bindings"
      (let (state (reduction-state
                    '((root 1 ((#f)))
                      (weight 5 ((#f 2 2 tag #f) (#f 2 3 tag #f)
                                 (#f 4 4 wrong #f) (1 2 2 tag #f))))
                    '(weight ?r ?x ?x tag ?_) '(sum ?x) '((#f 2))))
        (check-equal? (produce state 1000000 #f) (produce state 1000000 #t))
        (check-equal? (verify state (vector-ref state 4) 1000000 #f) 'valid)
        (for-each (lambda (budget)
                    (check-equal? (verify state (vector-ref state 4) budget #f)
                                  (verify state (vector-ref state 4) budget #t)))
                  (iota 60 1))))
    (test-case "aggregate operand may come from the successful outer prefix"
      (let (state (reduction-state '((root 1 ((3))) (weight 1 ((3) (4))))
                    '(weight ?r) '(sum ?r) '((3 3))))
        (check-equal? (produce state 1000000 #f) (produce state 1000000 #t))
        (check-equal? (verify state (vector-ref state 4) 1000000 #f) 'valid)))
    (test-case "all complete consumers equal direct arithmetic and frozen proofs"
      (for-each (lambda (scenario)
                  (let (state (stratified-prepare #f scenario))
                    (check-equal? (stratified-consume state scenario #t)
                                  (stratified-expected state scenario))
                    (check-equal? (stratified-consume state scenario #f)
                                  (stratified-expected state scenario))))
                '(wide produce cold forged small source)))
    (test-case "every checker budget boundary is unchanged"
      (let* ((state (stratified-prepare #f 'small)) (proof (vector-ref state 4)))
        (for-each (lambda (budget)
                    (check-equal? (verify state proof budget #f) (verify state proof budget #t)))
                  (iota 80 1))))
    (test-case "every independent finite replay budget boundary is unchanged"
      (with (#(snapshot spec rows finite _ old-finite) (stratified-prepare #f 'small))
        (for-each
         (lambda (budget)
           (check-equal?
            (candidate-verify-finite-evidence snapshot spec 'digest 'complete rows finite budget)
            (old-candidate-verify-finite-evidence snapshot spec 'digest 'complete rows old-finite budget)))
         (iota 80 1))))
    (test-case "every producer budget boundary and ordered witness is unchanged"
      (let (state (stratified-prepare #f 'small))
        (for-each (lambda (budget)
                    (check-equal? (produce state budget #f) (produce state budget #t)))
                  (iota 80 1))))
    (test-case "duplicate missing and wrong-relation reduction evidence is rejected"
      (let (state (stratified-prepare #f 'small))
        (for-each
         (lambda (ids)
           (let* ((proof (candidate-copy-pairs (vector-ref state 4)))
                  (node (car (last-pair (cadr proof))))
                  (reduction (cadr (list-ref node 4))))
             (set-car! (cdr reduction) ids)
             (check-equal? (verify state proof 1000000 #t) 'invalid)
             (check-equal? (verify state proof 1000000 #f) 'invalid)
             (for-each (lambda (budget)
                         (check-equal? (verify state proof budget #f) (verify state proof budget #t)))
                       (iota 30 1))))
         '((1 1) (1) (0 1) (1 3) (1 -1)))))
    (test-case "later invocations do not retain mutated supplied evidence"
      (let* ((state (stratified-prepare #f 'small)) (proof (vector-ref state 4))
             (row (caddr (car (last-pair (cadr proof))))))
        (check-equal? (verify state proof 1000000 #f) 'valid)
        (set-car! row 99)
        (check-equal? (verify state proof 1000000 #f) 'invalid)
        (set-car! row 1)
        (check-equal? (verify state proof 1000000 #f) 'valid)))))
