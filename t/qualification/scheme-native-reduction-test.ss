;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-ascent/program/scheme-language
                 relational-program relational-lattice-fragment
                 relational-fragment relational-compose relational-export
                 relational-admit relational-solve relational-query
                 relational-query-name relational-open-program-session
                 relational-program-session-run
                 relational-program-append-source!
                 relational-program-replace-source!
                 relational-program-query))

(export scheme-native-reduction-test)

(def (reduced-program)
  (relational-program
   (relation root (node) '((1) (2) (3)))
   (relation weight (node value) '((1 10) (1 20) (2 5)))
   (relation cardinality (node count))
   (relation total (node value))
   (rule (cardinality ?node ?count)
     (root ?node)
     (reduce ?count (count) (weight ?node ?value)))
   (rule (total ?node ?sum)
     (root ?node)
     (reduce ?sum (sum ?value) (weight ?node ?value)))
   (limits 16 32 64)))

(def (lattice-program rows)
  (relational-program
   (relation input (key value) rows)
   (lattice best (key value) [] max)
   (rule (best ?key ?value) (input ?key ?value))
   (limits 16 16 32)))

(def scheme-native-reduction-test
  (test-suite "checked reduction and lattice semantics"
    (test-case "count and sum group by an already bound key"
      (let (solution (relational-solve
                     (relational-admit (reduced-program))))
        (check-equal? (relational-query-name solution 'cardinality)
                      '((1 2) (2 1) (3 0)))
        (check-equal? (relational-query-name solution 'total)
                      '((1 30) (2 5) (3 0)))))
    (test-case "numeric reducer rejects a noninteger row"
      (let (program
            (relational-program
             (relation input (key value) '((1 symbol)))
             (relation result (value))
             (rule (result ?sum)
               (input ?key ?value)
               (reduce ?sum (sum ?value) (input ?key ?value)))
             (limits 8 8 16)))
        (check-exception
         (relational-solve (relational-admit program)) true)))
    (test-case "checked max lattice keeps the best value per key"
      (let (solution
            (relational-solve
             (relational-admit
              (lattice-program '((1 2) (1 5) (2 4))))))
        (check-equal? (relational-query-name solution 'best)
                      '((1 5) (2 4)))))
    (test-case "lattice fragment composes and remains instance local"
      (let* ((first (relational-lattice-fragment
                     'score 2 '((1 2) (1 5)) 'max))
             (second (relational-lattice-fragment
                      'score 2 '((2 4)) 'max))
             (program (relational-compose
                       (list first second) 8 8 16))
             (solution (relational-solve (relational-admit program))))
        (check-equal? (eq? (relational-export first 'score)
                          (relational-export second 'score)) #f)
        (check-equal? (relational-query solution first 'score)
                      '((1 5)))
        (check-equal? (relational-query solution second 'score)
                      '((2 4)))))
    (test-case "lattice source replacement keeps prior solved snapshot"
      (let* ((session
              (relational-open-program-session
               (lattice-program '((1 2) (1 5)))))
             (first (relational-program-session-run session)))
        (relational-program-append-source! session 'input '(1 7))
        (let (after-insert (relational-program-session-run session))
          (check-equal? (relational-program-query after-insert 'best)
                        '((1 7)))
          (check-equal? (relational-program-query first 'best)
                        '((1 5))))
        (relational-program-replace-source!
         session 'input '((1 3)))
        (let (second (relational-program-session-run session))
          (check-equal? (relational-program-query first 'best)
                        '((1 5)))
          (check-equal? (relational-program-query second 'best)
                        '((1 3))))))
    (test-case "unknown lattice join and invalid values reject"
      (check-exception
       (relational-lattice-fragment 'score 2 '((1 bad)) 'max) true)
      (check-exception
       (relational-lattice-fragment 'score 2 '((1 2)) 'other) true))))
