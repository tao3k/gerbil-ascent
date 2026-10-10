;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/error
        (only-in :clan/poo/object .o .ref)
        :gerbil-ascent/temporal/lens
        (prefix-in :gerbil-ascent/t/performance/temporal-replay/reference old-)
        :gerbil-ascent/t/performance/temporal-replay/fixture)
(export ascent-temporal-replay-test)
(def (replace-field data index value)
  (map (lambda (n x) (if (= n index) value x)) (iota (length data)) data))
(def ascent-temporal-replay-test
  (test-suite "Complete temporal certificate replay"
    (test-case "Complete public consumers agree with frozen operations and independent truth"
      (for-each (lambda (scenario)
        (let ((before (replay-prepare #t scenario)) (after (replay-prepare #f scenario)))
          (check-equal? (replay-consume before scenario #t) (replay-expected before scenario))
          (check-equal? (replay-consume after scenario #f) (replay-expected after scenario))))
        '(verify compare fork empty small partial solve)))
    (test-case "All two-node graphs preserve whole-cut cycle rejection and root verdicts"
      (for-each (lambda (mask)
        (let* ((edges (filter-map (lambda (n)
                       (and (bit-set? n mask) (list (if (< n 2) 'a 'b) (if (even? n) 'a 'b))))
                       (iota 4)))
               (l (temporal-lens 0 'clock 0 10 9 'cut '(a b) 4 #t))
               (s (temporal-source 'source 0 'clock '((a 0 0) (b 0 0)) edges)))
          (for-each (lambda (root)
            (let ((a (temporal-solve l s root)) (b (old-temporal-solve l s root)))
              (check-equal? (temporal-projection a) (temporal-projection b))
              (check-equal? (temporal-verify l s root a) (if (eq? (temporal-status a) 'complete) 'valid 'invalid))
              (check-equal? (old-temporal-verify l s root a) (if (eq? (temporal-status a) 'complete) 'valid 'invalid)))) '(a b)))) (iota 16)))
    (test-case "Every projected coordinate is bound even when rows are equal"
      (let* ((state (replay-prepare #f 'small)) (l (vector-ref state 0))
             (s (vector-ref state 1)) (root (vector-ref state 2))
             (answer (vector-ref state 3)) (data (temporal-projection answer)))
        (for-each (lambda (entry)
          (let* ((changed (replace-field data (car entry) (cdr entry)))
                 (forged (.o (:: @ answer) projection: (lambda () changed))))
            (check-equal? (temporal-verify l s root forged) 'invalid)
            (check-equal? (old-temporal-verify l s root forged) 'invalid)))
          (list (cons 0 'partial) (cons 1 '(0 clock 0 10 9 other-cut (node0 node1) 12 #t))
                (cons 2 '(other-source 0 clock ((node0 0 0) (node1 0 0)) ((node0 node1))))
                (cons 3 'node1) (cons 4 []) (cons 5 '(forged-frontier))
                (cons 6 '(hypothetical forged-source 0 forged-cut))))))
    (test-case "Empty receipts still require independent closure and current binding"
      (let* ((state (replay-prepare #f 'empty)) (answer (vector-ref state 3))
             (forged (.o (:: @ answer) receipt: #f)))
        (check-equal? (temporal-verify (vector-ref state 0) (vector-ref state 1) (vector-ref state 2) forged) 'invalid)
        (check-equal? (old-temporal-verify (vector-ref state 0) (vector-ref state 1) (vector-ref state 2) forged) 'invalid)))
    (test-case "Detached public rows cannot edit a later verified cut"
      (let* ((state (replay-prepare #f 'small)) (answer (vector-ref state 3)))
        (set-car! (car (temporal-rows answer)) 'mutated)
        (check-equal? (temporal-verify (vector-ref state 0) (vector-ref state 1) (vector-ref state 2) answer) 'valid)))
    (test-case "Incomplete POO projections reject before demanding an absent receipt slot"
      (let* ((state (replay-prepare #f 'partial))
             (payload-value (temporal-projection (vector-ref state 3)))
             (answer (.o kind: 'ascent.temporal-answer.v1 projection: (lambda () payload-value))))
        (check-equal? (temporal-verify (vector-ref state 0) (vector-ref state 1) (vector-ref state 2) answer) 'invalid)
        (check-equal? (old-temporal-verify (vector-ref state 0) (vector-ref state 1) (vector-ref state 2) answer) 'invalid)))))
