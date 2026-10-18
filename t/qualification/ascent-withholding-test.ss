;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-suite test-case)
        :gerbil-ascent/candidate/withholding
        :gerbil-ascent/candidate/feedback
        (only-in :gerbil-ascent/candidate/types candidate-rejection?
                 candidate-rejection-diagnostic reasoning-diagnostic-code
                 reasoning-snapshot-valid? reasoning-snapshot-relations)
        (only-in :gerbil-ascent/candidate/reasoning reasoning-source-snapshot
                 reasoning-attempt reasoning-receipt-status reasoning-receipt-rows
                 reasoning-verify-finite-receipt))
(export ascent-withholding-test)
(def (refusal thunk)
  (try (thunk) #f
       (catch (e) (if (candidate-rejection? e)
                    (reasoning-diagnostic-code (candidate-rejection-diagnostic e))
                    (raise e)))))
(def (subset mask) (filter (lambda (v) (not (zero? (bitwise-and mask (arithmetic-shift 1 v))))) '(0 1 2)))
(def (rows source name) (caddr (assq name (reasoning-snapshot-relations source))))
(def ascent-withholding-test
  (test-suite "BRINK finite whole-batch withholding"
    (test-case "all 64 removal/protection pairs agree with independent sets"
      (let (source (reasoning-source-snapshot 'facts 0 '((item 1 ((0) (1) (2))))))
        (for-each (lambda (hm)
          (for-each (lambda (bm)
            (let* ((heads (subset hm)) (body (map (lambda (v) (list 'item v)) (subset bm)))
                   (g (map (lambda (v) (list (list 'item v) body)) heads))
                   (overlap (ormap (lambda (v) (member v (subset bm))) heads)))
              (cond
               ((and (pair? heads) (null? body))
                (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 g))) 'invalid-grounding))
               (overlap (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 g))) 'withheld-head-protected))
               (else (let (cut (reasoning-withhold-source-snapshot source 1 g))
                 (check-equal? (rows cut 'item) (map list (filter (lambda (v) (not (member v heads))) '(0 1 2)))))))
              (check-equal? (reasoning-snapshot-valid? source) #t))) (iota 8))) (iota 8))))
    (test-case "cross-grounding conflicts reject the whole batch"
      (let (source (reasoning-source-snapshot 'facts 0 '((item 1 ((0) (1) (2))))))
        (for-each (lambda (g)
          (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 g))) 'withheld-head-protected))
          '((((item 0) ((item 2))) ((item 1) ((item 0))))
            (((item 1) ((item 0))) ((item 0) ((item 2))))))
        (check-equal? (rows source 'item) '((0) (1) (2)))))
    (test-case "withheld direct answer remains recoverable and full gold answers survive"
      (let* ((source (reasoning-source-snapshot 'family 0
                      '((parent 2 ((0 1))) (child 2 ((1 2) (1 3))) (sibling 2 ((0 2) (0 3))))))
             (cut (reasoning-withhold-source-snapshot source 1
                    '(((sibling 0 2) ((parent 0 1) (child 1 2))))))
             (p '(candidate (relation answer 2)
                   (rule (answer ?x ?y) (sibling ?x ?y))
                   (rule (answer ?x ?y) (parent ?x ?z) (child ?z ?y))
                   (query answer 0 ?y) (limits 16 32 64)))
             (lookup '(candidate (relation answer 2)
                        (rule (answer ?x ?y) (sibling ?x ?y))
                        (query answer 0 ?y) (limits 16 32 64)))
             (gold (rows source 'sibling))
             (receipt (reasoning-attempt cut p 10000 10000)))
        (check-equal? (rows cut 'sibling) '((0 3)))
        (check-equal? (rows cut 'parent) '((0 1)))
        (check-equal? (reasoning-receipt-status receipt) 'complete)
        (check-equal? (reasoning-feedback-status (reasoning-compare-rows cut p receipt gold)) 'match)
        (check-equal? (reasoning-verify-finite-receipt receipt cut p 10000) 'valid)
        (let (feedback (reasoning-compare-rows cut lookup (reasoning-attempt cut lookup #f) gold))
          (check-equal? (reasoning-feedback-status feedback) 'mismatch)
          (check-equal? (reasoning-feedback-missing feedback) '((0 2))))
        (check-equal? (reasoning-feedback-reason (reasoning-compare-rows source p receipt gold)) 'unbound)))
    (test-case "malformed, stale, missing and bounded inputs never alter source"
      (let* ((source (reasoning-source-snapshot 'zero 0 '((flag 0 (())) (item 1 ((1))))))
             (cut (reasoning-withhold-source-snapshot source 1 '(((flag) ((item 1)))))))
        (check-equal? (rows cut 'flag) [])
        (check-equal? (rows cut 'item) '((1))))
      (let (source (reasoning-source-snapshot 'facts 0 '((item 1 ((0) (0) (1))))))
        (check-equal? (rows (reasoning-withhold-source-snapshot source 1 '(((item 0) ((item 1))))) 'item) '((1)))
        (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 0 []))) 'invalid-generation)
        (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 '(((item 2) ((item 1))))))) 'unobserved-ground-atom)
        (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 '(((item 0) ((item 2))))))) 'unobserved-ground-atom)
        (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 '(((item 0 2) ((item 1))))))) 'invalid-ground-atom)
        (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 (make-list 65 '((item 0) ((item 1))))))) 'invalid-groundings)
        (let (cycle (list '((item 0) ((item 1)))))
          (set-cdr! cycle cycle)
          (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 cycle))) 'invalid-groundings))
        (let* ((g (list (list (list 'item 0) (list (list 'item 1)))))
               (cut (reasoning-withhold-source-snapshot source 1 g)))
          (set-car! (caar g) 'changed)
          (check-equal? (reasoning-snapshot-valid? cut) #t))
        (check-equal? (rows source 'item) '((0) (0) (1)))
        (set-car! (car (rows source 'item)) 9)
        (check-equal? (refusal (lambda () (reasoning-withhold-source-snapshot source 1 []))) 'invalid-snapshot)))))
