;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-binding-reference-evaluate
                 ascent-reference-evaluate-program)
        (only-in :gerbil-ascent/t/qualification/ascent-rule-program-fixture
                 ascent-rule-fixture-program))
(export ascent-binding-program-test)

;;; A semantic differential under Core's default Case profile. The existing
;;; rule-program module independently keeps its unchanged 2000 ms admission
;;; budget; passing this comparison does not qualify that timing boundary.
(def ascent-binding-program-test
  (test-suite "ASCENT prepared binding across mixed rule clauses"
    (poo-flow-test-case "all mixed-program relations match raw binding and goldens"
      (let* ((source '((1 2 "a") (2 3 "b") (3 3 "c") (1 2 "a")))
             (program (ascent-rule-fixture-program source))
             (old (ascent-reference-evaluate-program program))
             (new (gerbil-ascent-evaluate-program program))
             (goldens
              (list (cons 'edge source)
                    '(node (1) (2) (3))
                    '(labelled (1 3 "a" "b") (2 3 "b" "c") (3 3 "c" "c"))
                    '(cycle (3)) '(hot (1)) '(selected (1 2))
                    '(choice (1 2) (1 3) (2 1) (2 3) (3 1) (3 2))
                    '(generated (1) (2) (3))
                    '(dependent (2 0) (3 0) (3 1))
                    '(successor (1 2) (2 3) (3 4))
                    '(blocked (3 3)) '(allowed (1 2) (2 3))
                    '(denied (3 3)) '(safe-reach (1 2) (2 3) (1 3))
                    '(reach (1 2) (2 3) (3 3) (1 3)))))
        (for-each
         (lambda (golden)
           (let* ((name (car golden))
                  (expected (cdr golden))
                  (old-rows ((.ref old 'rows-of) name))
                  (new-rows ((.ref new 'rows-of) name)))
             (check-equal? new-rows old-rows)
             (check-equal? (length new-rows) (length expected))
             (for-each (lambda (row)
                         (check-equal? (not (not (member row new-rows))) #t))
                       expected)
             (displayln "PROGRAM-BINDING-PARITY " name
                        " rows=" (length new-rows))))
         goldens)))))
