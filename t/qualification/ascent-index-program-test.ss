;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow-foundation/module-system/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program ascent-index-alist-provider)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-index-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export ascent-index-program-test)

(def ascent-index-program-test
  (test-suite "ASCENT indexed relation access"
    (poo-flow-test-case "bound-column index preserves two-hop join semantics"
      (let* ((program (ascent-index-fixture-program))
             (rows ((.ref (gerbil-ascent-evaluate-program program) 'rows-of)
                    'two-hop)))
        (check-equal? (length rows) 49)
        (check-equal? (not (not (member '(0 2) rows))) #t)
        (check-equal? (not (not (member '(48 50) rows))) #t)
        (check-equal? (member '(0 3) rows) #f)))
    (poo-flow-test-case "a custom alist Provider replaces the physical index"
      (let* ((builds 0)
             (provider
              (ascent-index-alist-provider
               (lambda () (set! builds (+ builds 1)))))
             (rows
              ((.ref (gerbil-ascent-evaluate-program
                      (ascent-index-fixture-program 50 provider))
                     'rows-of)
               'two-hop)))
        (check-equal? (> builds 0) #t)
        (check-equal? (length rows) 49)
        (check-equal? (not (not (member '(48 50) rows))) #t)))
    (poo-flow-test-case "malformed Provider values fail at the boundary"
      (check-exception (gerbil-ascent-index-provider #f #f) true)
      (check-exception
       (gerbil-ascent-evaluate-program
        (ascent-index-fixture-program
         50 (gerbil-ascent-index-provider
             (lambda (_rows _columns) 'broken)
             (lambda (_index _key) 'broken))))
       true))))
