;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :std/list/list append-map)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot)
        (only-in :gerbil-ascent/candidate/types reasoning-snapshot-relations)
        (only-in :gerbil-ascent/candidate/program candidate-inspect)
        (only-in :gerbil-ascent/candidate/funs candidate-same-row-set?)
        :gerbil-ascent/candidate/finite-evidence
        (rename-in (only-in :gerbil-ascent/t/performance/finite-replay/reference-funs
                           candidate-same-row-set?)
                   (candidate-same-row-set? old-same?))
        (rename-in (only-in :gerbil-ascent/t/performance/finite-replay/reference
                           candidate-finite-evidence candidate-verify-finite-evidence
                           finite-evidence-status finite-evidence-closure)
                   (candidate-finite-evidence old-generate)
                   (candidate-verify-finite-evidence old-verify)
                   (finite-evidence-status old-status)
                   (finite-evidence-closure old-closure)))
(export scheme-finite-replay-test)

(def (sequences size)
  (if (zero? size) [[]]
      (append-map (lambda (tail) (map (lambda (n) (cons (list n) tail)) '(0 1 2)))
                  (sequences (- size 1)))))
(def (support rows)
  (foldl (lambda (row bits) (bitwise-ior bits (expt 2 (car row)))) 0 rows))
(def (parity snapshot spec expected budget status)
  (let ((a (old-generate snapshot spec 'replay 'complete expected budget))
        (b (candidate-finite-evidence snapshot spec 'replay 'complete expected budget)))
    (check-equal? (old-status a) status)
    (check-equal? (finite-evidence-status b) status)
    (check-equal? (finite-evidence-closure b) (old-closure a))
    (when (eq? status 'complete)
      (check-equal? (old-verify snapshot spec 'replay 'complete expected a budget) 'valid)
      (check-equal? (candidate-verify-finite-evidence snapshot spec 'replay 'complete expected b budget) 'valid))
    b))
(def (growth snapshot derived-limit)
  (candidate-inspect snapshot
    `(candidate (relation p 1) (rule (p ?x) (seed ?x))
                (rule (p ?next) (p ?x) (one ?one) (bound ?limit)
                      (compute ?next (+ ?x ?one)) (where (< ?next ?limit)))
                (query p ?x) (limits 8 ,derived-limit 64))))

(def scheme-finite-replay-test
  (test-suite "Ordered finite replay and row support"
    (test-case "14641 row-list pairs retain length and support semantics"
      (let (rows (map list (list #t #f 'a #\a -1)))
        (check-equal? (candidate-same-row-set? rows (reverse rows)) #t)
        (check-equal? (old-same? rows (reverse rows)) #t)
        (check-equal? (candidate-same-row-set? rows '((#t) (#f) (a) (a) (-1))) #f))
      (let (corpus (append-map sequences (iota 5)))
        (check-equal? (length corpus) 121)
        (for-each
         (lambda (a position)
           (for-each
            (lambda (b)
              (let (expected (and (= (length a) (length b)) (= (support a) (support b))))
                (check-equal? (old-same? a b) expected)
                (check-equal? (candidate-same-row-set? a b) expected))) corpus)
           (when (zero? (modulo (+ position 1) 11))
             (displayln "ROW-SUPPORT-CHECKED " (+ position 1) "/121") (force-output)))
         corpus (iota 121))))
    (test-case "duplicate seeds keep insertion order and exact probe budgets"
      (for-each
       (lambda (count)
         (let* ((unique (map list (reverse (iota count))))
                (input (append unique unique))
                (expected (append unique '((-1))))
                (snapshot (reasoning-source-snapshot 'seeds count (list (list 's 1 input))))
                (spec (candidate-inspect snapshot
                        '(candidate (relation p 1) (fact s 0) (fact s -1)
                                    (rule (p ?x) (s ?x)) (rule (p ?x) (p ?x))
                                    (query p ?x) (limits 32 32 64))))
                ;; Duplicate source/fact rows cost no replay probe. Two
                ;; rounds each probe the deduplicated s and p frontiers.
                (budget (* 4 (+ count 1))))
           (let (certificate (parity snapshot spec expected budget 'complete))
             (check-equal? (finite-evidence-closure certificate)
                           (list (list 's 1 expected) (list 'p 1 expected))))
           (parity snapshot spec expected (- budget 1) 'bounded)
           (displayln "REPLAY-SEEDS-CHECKED " count "/8") (force-output)))
       (iota 8 1)))
    (test-case "recursive frontiers retain every round and derived-row boundary"
      (for-each
         (lambda (count)
           (let* ((snapshot (reasoning-source-snapshot 'growth count
                             (list '(seed 1 ((0))) '(one 1 ((1)))
                                   (list 'bound 1 (list (list count))))))
                  (spec (growth snapshot count))
                  (expected (map list (iota count)))
                  ;; Each p row probes p/one/bound, computes, and tests the
                  ;; limit. The retained frontiers have sizes 1..n.
                  (budget (+ count (* 5 (quotient (* count (+ count 1)) 2)))))
             (let (certificate (parity snapshot spec expected budget 'complete))
               (check-equal? (finite-evidence-closure certificate)
                             (list '(seed 1 ((0))) '(one 1 ((1)))
                                   (list 'bound 1 (list (list count))) (list 'p 1 expected))))
             (parity snapshot spec expected (- budget 1) 'bounded)
             (parity snapshot (growth snapshot (- count 1)) expected budget 'bounded)
             (displayln "REPLAY-GROWTH-CHECKED " count "/12") (force-output)))
         (iota 11 2)))
    (test-case "verified closure owns rows independently of certificate and source"
      (let* ((snapshot (reasoning-source-snapshot 'ownership 1 '((s 1 ((1) (2))))))
             (spec (candidate-inspect snapshot '(candidate (query s ?x) (limits 8 16 32))))
             (certificate (parity snapshot spec '((1) (2)) 32 'complete)))
        (let-values (((verdict closure)
                      (candidate-verified-finite-closure snapshot spec 'replay 'complete
                                                         '((1) (2)) certificate 32)))
          (check-equal? verdict 'valid)
          (set-car! (car (caddr (car (finite-evidence-closure certificate)))) 99)
          (check-equal? closure '((s 1 ((1) (2)))))
          (check-equal? (reasoning-snapshot-relations snapshot) '((s 1 ((1) (2)))))
          (check-equal? (candidate-verify-finite-evidence snapshot spec 'replay 'complete
                                                       '((1) (2)) certificate 32) 'invalid))))))
