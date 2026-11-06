;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/candidate/support-cut grounded-support-withdraw!)
        (only-in :gerbil-ascent/t/performance/support-cut/fixture cut-prepare cut-consume cut-verify!))
(export ascent-support-cut-test)
(def ascent-support-cut-test
  (test-suite "Dependency-driven founded withdrawal transactions"
    (test-case "cycles restore only from remaining source or empty rule support"
      (for-each
       (lambda (alternative)
         (let* ((edges (append '((0 source gone ()) (1 rule seed (0))
                                (1 rule back (2)) (2 rule cycle (1))) alternative))
                (alive (list->hash-table-eqv '((0 . #t) (1 . #t) (2 . #t) (3 . #t))))
                (affected (list->hash-table-eqv '((0 . #t))))
                (removed (list->hash-table '((gone . #t)))))
           (grounded-support-withdraw! edges '(0) affected alive removed void)
           (check (map (cut hash-get alive <>) '(0 1 2 3))
                  => (if (null? alternative) '(#f #f #f #t) '(#f #t #t #t)))))
       '(() ((3 source kept ()) (1 rule alternate (3))) ((1 rule fact ())))))
    (test-case "repeated premises and repeated source seeds cannot reanimate a cycle"
      (let ((alive (list->hash-table-eqv '((0 . #t) (1 . #t) (2 . #t))))
            (affected (list->hash-table-eqv '((0 . #t))))
            (removed (list->hash-table '((gone . #t)))))
        (grounded-support-withdraw!
         '((0 source gone ()) (1 rule wide (0 0 0)) (2 rule derived (1)) (1 rule back (2)))
         '(0 0) affected alive removed void)
        (check (hash-length alive) => 0)))
    (test-case "complete withdrawal preview publication compaction and height consumers match"
      (for-each (lambda (scenario)
                  (let ((prior (cut-prepare #t scenario)) (current (cut-prepare #f scenario)))
                    (cut-verify! prior scenario) (cut-verify! current scenario)
                    (check (cut-consume current scenario) => (cut-consume prior scenario))))
                '(withdraw restore rejected small)))))
