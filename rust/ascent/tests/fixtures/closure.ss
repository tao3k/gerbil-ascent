;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Independent existing Scheme evaluator. This is qualification, not transport.
(import :gerbil-ascent/program/objects :gerbil-ascent/program/session
        (only-in :clan/poo/object .ref))
(export main)
(def (solve edges)
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y)) (z (gerbil-ascent-variable 'z))
         (program (gerbil-ascent-program
           (list (gerbil-ascent-relation 'edge 2 edges) (gerbil-ascent-relation 'reach 2 []))
           (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y)))
                    (list (gerbil-ascent-atom 'edge (list x y))))
                 (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x z)))
                    (list (gerbil-ascent-atom 'reach (list x y)) (gerbil-ascent-atom 'edge (list y z)))))
           1000000 1000000 1000000 '(edge)))
         (session (gerbil-ascent-open-session program))
         (result (gerbil-ascent-session-run-timeout session 30000000000)))
    (unless (.ref result 'finished) (error "Scheme qualification exhausted deadline"))
    ((.ref result 'rows-of) 'reach)))
(def (main . arguments)
  (let loop ()
    (let (input (read))
      (unless (eof-object? input)
        (for-each (lambda (row) (display (car row)) (display "\t") (display (cadr row)) (newline)) (solve input))
        (display "--\n")
        (loop)))))
