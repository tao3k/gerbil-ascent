;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case
                 poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-lattice-program-fixture
                 ascent-lattice-fixture-evaluate)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-lattice gerbil-ascent-relation
                 gerbil-ascent-program gerbil-ascent-open-session
                 gerbil-ascent-session-run
                 gerbil-ascent-session-append-source!))

(export ascent-lattice-program-test)

(def (shortest edges)
  ((.ref (ascent-lattice-fixture-evaluate edges) 'rows-of) 'shortest))

(def ascent-lattice-program-test
  (test-suite "ASCENT lattice fixed point"
    (poo-flow-test-case "recursive shortest paths replace weaker key values"
      (let (rows (shortest '((1 2 3) (1 3 1) (3 2 1)
                             (2 4 1) (3 4 5))))
        (check-equal? (length rows) 6)
        (check-equal? (not (not (member '(1 2 2) rows))) #t)
        (check-equal? (not (not (member '(1 4 3) rows))) #t)
        (check-equal? (member '(1 4 6) rows) #f)))
    (poo-flow-test-case "empty and invalid lattice declarations"
      (check-equal? (shortest []) [])
      (check-exception (gerbil-ascent-lattice 'bad 0 [] min) true)
      (check-exception (gerbil-ascent-lattice 'bad 2 '((1)) min)
                       true))
    (poo-flow-test-case "session rejects source updates in lattice programs"
      (let (session
            (gerbil-ascent-open-session
             (gerbil-ascent-program
              (list (gerbil-ascent-relation 'source 2 '((1 2)))
                    (gerbil-ascent-lattice 'best 2 [] min))
              [] 4 4 8)))
        (gerbil-ascent-session-run session)
        (check-exception
         (gerbil-ascent-session-append-source! session 'source '(2 3))
         true)))))
