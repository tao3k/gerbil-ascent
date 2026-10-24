;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :clan/poo/object .o .mix .ref)
        (only-in :gerbil-ascent/t/qualification/ascent-module-source
                 ascent-origin-reach-program)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-evaluate-program))

(export ascent-module-program-test)

(def ascent-module-program-test
  (test-suite "ASCENT Gerbil module and lexical scope"
    (test-case "reused module captures each caller origin"
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
        (check-equal? (member '(1 2) second) #f)))
    (test-case "POO slot refinement creates a second input snapshot"
      (let* ((base (ascent-origin-reach-program '((1 2)) 1))
             (relation-values (.ref base 'relations))
             (edge (car relation-values))
             (updated-edge
              (.o (:: @ edge) rows: '((1 2) (2 3))))
             (updated-program
              (.o (:: @ base)
                  relations: (cons updated-edge (cdr relation-values))))
             (first
              ((.ref (gerbil-ascent-evaluate-program base) 'rows-of)
               'reach))
             (second
              ((.ref (gerbil-ascent-evaluate-program updated-program) 'rows-of)
               'reach)))
        (check-equal? first '((1 2)))
        (check-equal? (length second) 2)
        (check-equal? (not (not (member '(1 3) second))) #t)))
    (test-case "C4 combines independent ASCENT declaration refinements"
      (let* ((base (ascent-origin-reach-program '((1 2)) 1))
             (relation-values (.ref base 'relations))
             (edge (car relation-values))
             (source-edge
              (.o (:: @ edge) rows: '((1 2) (2 3))))
             (typed-edge
              (.o (:: @ edge)
                  field-predicates: (list integer? integer?)))
             (composed-edge (.mix source-edge typed-edge))
             (source-profile
              (.o (:: @ base)
                  relations:
                  (cons composed-edge
                        (cdr relation-values))))
             (budget-profile
              (.o (:: @ base) max-output-facts: 12))
             (composed (.mix source-profile budget-profile))
             (rows ((.ref (gerbil-ascent-evaluate-program composed) 'rows-of)
                    'reach)))
        (check-equal? (.ref composed 'max-output-facts) 12)
        (check-equal? (length (.ref composed-edge 'field-predicates)) 2)
        (check-equal? (length rows) 2)
        (check-equal? (not (not (member '(1 3) rows))) #t)))))
