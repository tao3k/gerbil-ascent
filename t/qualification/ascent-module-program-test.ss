;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow-foundation/module-system/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-module-source
                 ascent-origin-reach-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export ascent-module-program-test)

(def ascent-module-program-test
  (test-suite "ASCENT Gerbil module and lexical scope"
    (poo-flow-test-case "reused module captures each caller origin"
      (let* ((edges '((1 2) (2 3) (3 4) (2 5)))
             (first
              ((.ref (gerbil-ascent-evaluate-program
                      (ascent-origin-reach-program edges 1)) 'rows-of)
               'reach))
             (second
              ((.ref (gerbil-ascent-evaluate-program
                      (ascent-origin-reach-program edges 2)) 'rows-of)
               'reach)))
        (check-equal? (length first) 4)
        (check-equal? (length second) 3)
        (check-equal? (not (not (member '(1 5) first))) #t)
        (check-equal? (not (not (member '(2 5) second))) #t)
        (check-equal? (member '(1 2) second) #f)))))
