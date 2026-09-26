;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow-foundation/module-system/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-mutual-program-fixture
                 ascent-mutual-evaluate))

(export ascent-mutual-program-test)

(def (same-rows? left right)
  (and (= (length left) (length right))
       (andmap (lambda (row) (member row right)) left)))

(def ascent-mutual-program-test
  (test-suite "ASCENT mutually recursive relations"
    (poo-flow-test-case "cycle reaches a fixed point across two relations"
      (let* ((result (ascent-mutual-evaluate
                      '((1 2) (2 3) (3 1))))
             (rows-of (.ref result 'rows-of)))
        (check-equal? (not (not (same-rows? (rows-of 'path0)
                                           '((1 1) (1 2) (1 3)
                                             (2 1) (2 2) (2 3)
                                             (3 1) (3 2) (3 3))))) #t)
        (check-equal? (length (rows-of 'path1)) 9)))
    (poo-flow-test-case "source order does not change the fixed point"
      (let* ((first (ascent-mutual-evaluate
                     '((1 2) (2 3) (3 1))))
             (reverse-source (ascent-mutual-evaluate
                              '((3 1) (2 3) (1 2)))))
        (for-each
         (lambda (name)
           (check-equal?
            (not (not (same-rows? ((.ref first 'rows-of) name)
                                  ((.ref reverse-source 'rows-of) name))))
            #t))
         '(path0 path1))))))
