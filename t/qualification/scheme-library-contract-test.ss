;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One finite specification for the common native/candidate subset.
;;; The matrix below does not call an ASCENT evaluator to obtain expectations.
(import (only-in :std/test check-equal? check-exception test-suite test-case)
        (only-in :gerbil-ascent/program/interface
                 relational-program relational-fragment relational-compose
                 relational-admit relational-solve relational-query-name
                 relational-query relational-open-program-session
                 relational-program-session-run relational-program-transaction!
                 relational-program-query)
        (only-in :gerbil-ascent/candidate/reasoning
                 reasoning-source-snapshot reasoning-attempt
                 reasoning-receipt-status reasoning-receipt-rows
                 reasoning-receipt-bound?
                 reasoning-receipt-stratified
                 reasoning-stratified-evidence-status
                 reasoning-verify-finite-receipt
                 reasoning-verify-stratified-receipt))

(import :gerbil-ascent/t/qualification/scheme-library-contract-fixture)
(export scheme-library-contract-test candidate weights support-phases
        support-totals contract-snapshot study-cases study-repair-seed study-filter-seed
        study-mutants model-summary)

(def scheme-library-contract-test
  (test-suite "native and candidate common semantic contract"
    (test-case "completed fresh and retained lifecycles preserve every published snapshot"
      (check-lifecycle (application-lifecycle #f))
      (check-lifecycle (application-lifecycle #t)))
    (test-case "eight diagnostic graphs share one finite model"
      (for-each
       (lambda (mask)
         (check-all mask (edges-for-mask mask) '((0 2)) weights roots)
         (displayln "CONTRACT-PROGRESS " mask)
         (force-output))
       '(0 1 3 7 24 31 47 63)))
    (test-case "blocked odd and equal-weight states discriminate admitted mistakes"
      (for-each
       (lambda (generation state)
         (apply check-all generation state)
         (displayln "DISCRIMINATOR-PROGRESS " generation)
         (force-output))
       '(0 1 2 3 4 5 6) study-cases)
      (for-each
       (lambda (mutant)
         (let (mismatches 0)
           (for-each
            (lambda (generation state)
              (let* ((source (apply contract-snapshot generation state))
                     (proposal (cdr mutant))
                     (receipt (reasoning-attempt source proposal 100000 20000)))
                (check-equal? (reasoning-receipt-status receipt) 'complete)
                (check-equal? (reasoning-verify-finite-receipt receipt source proposal 20000) 'valid)
                (check-equal? (reasoning-verify-stratified-receipt receipt source proposal 20000) 'valid)
                (unless (same-set? (reasoning-receipt-rows receipt)
                                  (apply model-summary state))
                  (set! mismatches (+ mismatches 1)))
                (displayln "MUTANT-PROGRESS " (car mutant) " " generation)
                (force-output)))
            '(0 1 2 3 4 5 6) study-cases)
           (check-equal? (> mismatches 0) #t)
           (displayln "MUTANT-DISCRIMINATED " (car mutant))
           (force-output)))
       study-mutants))
    (test-case "multi-source withdrawal and failed transaction are atomic"
      (let* ((edges '((0 1) (1 2)))
             (session
              (relational-open-program-session
               (native-program edges '((0 2)) weights roots)))
             (first (relational-program-session-run session))
             (expected-first (model-summary edges '((0 2)) weights roots))
             (second
              (relational-program-transaction!
               session (list (cons 'edge '((0 1)))
                             (cons 'blocked '())
                             (cons 'weight '((1 8) (2 6))))))
             (expected-second
              (model-summary '((0 1)) '() '((1 8) (2 6)) roots)))
        (check-equal?
         (same-set? (relational-program-query first 'summary)
                    expected-first) #t)
        (check-equal?
         (same-set? (relational-program-query second 'summary)
                    expected-second) #t)
        (check-equal?
         (same-set? (candidate-result 2 '((0 1)) '()
                                      '((1 8) (2 6)) roots)
                    expected-second) #t)
        (check-exception
         (relational-program-transaction!
          session (list (cons 'edge '((0 1) (9 "bad")))
                        (cons 'root '((0))))) true)
        (check-equal?
         (same-set? (relational-program-query
                     (relational-program-session-run session) 'summary)
                    expected-second) #t)
        (check-equal?
         (same-set? (relational-program-query first 'summary)
                    expected-first) #t)))
    (test-case "alternate and last support withdrawal preserve snapshot binding"
      (let* ((phases support-phases)
             (totals support-totals)
             (source-roots '((0)))
             (session
              (relational-open-program-session
               (native-program (car phases) '() weights source-roots)))
             (first (let (value (relational-program-session-run session))
                      (check-equal? (relational-program-query value 'summary) '((0 20)))
                      (displayln "SUPPORT-CHECKED initial-native") (force-output)
                      value))
             (snapshot
              (contract-snapshot 0 (car phases) '() weights source-roots))
             (receipt (let (value (reasoning-attempt snapshot candidate 100000 20000))
                        (check-equal? (reasoning-receipt-status value) 'complete)
                        (check-equal? (reasoning-receipt-rows value) '((0 20)))
                        (displayln "SUPPORT-CHECKED initial-candidate") (force-output)
                        value)))
        (for-each
         (lambda (generation edges total)
           (let* ((expected (list (list 0 total)))
                  (current
                   (if (zero? generation) first
                     (relational-program-transaction!
                      session (list (cons 'edge edges))))))
             (check-equal?
              (model-summary edges '() weights source-roots) expected)
             (check-all generation edges '() weights source-roots)
             (check-equal?
              (same-set? (relational-program-query current 'summary)
                         expected) #t)))
         '(0 1 2 3) phases totals)
        (check-equal? (relational-program-query first 'summary) '((0 20)))
        (check-equal? (reasoning-receipt-rows receipt) '((0 20)))
        ;; Same answer after removing one support does not preserve authority.
        (let (changed
              (contract-snapshot 1 (cadr phases) '() weights source-roots))
          (check-equal? (reasoning-receipt-bound? receipt changed candidate) #f)
          (check-equal?
           (reasoning-verify-finite-receipt receipt changed candidate 20000)
           'invalid)
          (check-equal?
           (reasoning-verify-stratified-receipt receipt changed candidate 20000)
           'invalid))))
    (test-case "resource exhaustion is never a completed answer"
      (let* ((snapshot
              (reasoning-source-snapshot
               'contract 1
               '((edge 2 ((0 1) (1 2)))
                 (blocked 2 ())
                 (weight 2 ((1 4) (2 6)))
                 (root 1 ((0) (1) (2))))))
             (small
              (append (reverse (cdr (reverse candidate)))
                      '((limits 16 1 128))))
             (receipt (reasoning-attempt snapshot small))
             (session
              (relational-open-program-session
               (native-program '((0 1) (1 2)) '()
                               '((1 4) (2 6)) roots)))
             (complete (relational-program-session-run session)))
        (check-equal? (reasoning-receipt-status receipt) 'unknown)
        (check-equal? (reasoning-receipt-rows receipt) '())
        (check-exception
         (relational-program-transaction!
          session
          (list (cons 'edge
                      (map (lambda (i) (list i (+ i 1)))
                           (iota 17))))) true)
        (check-equal?
         (same-set?
          (relational-program-query
           (relational-program-session-run session) 'summary)
          (relational-program-query complete 'summary)) #t)))))
