;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object (only-in :std/error Error? Error-message)
        :gerbil-ascent/program/objects
        :gerbil-ascent/program/source-snapshot
        :gerbil-ascent/program/session
        :gerbil-ascent/t/performance/source-snapshot/fixture)
(export ascent-source-snapshot-test)
(def (failure-message? message)
  (lambda (failure) (and (Error? failure) (equal? (Error-message failure) message))))
(def ascent-source-snapshot-test
  (test-suite "Persistent source preparation and atomic adoption"
    (test-case "complete retained consumers match the frozen engine and Session"
      (for-each
       (lambda (scenario)
         (let ((old (snapshot-prepare #t scenario)) (new (snapshot-prepare #f scenario)))
           (for-each (lambda (_)
                       (check (snapshot-consume old scenario)
                              => (snapshot-consume new scenario))) (iota 3))))
       '(transaction dense replay positive small)))
    (test-case "unchanged declarations and cuts share private identity"
      (let* ((program (snapshot-program 4 #f))
             (snapshot (gerbil-ascent-source-snapshot program))
             (rows (vector-copy (source-snapshot-rows snapshot))))
        (check (eq? snapshot (gerbil-ascent-prepare-source-snapshot snapshot rows)) => #t)
        (vector-set! rows 1 '((0)))
        (let* ((next (gerbil-ascent-prepare-source-snapshot snapshot rows))
               (before (.ref program 'relations))
               (after (.ref (source-snapshot-program next) 'relations)))
          (for-each (lambda (a b index) (check (eq? a b) => (not (= index 1))))
                    before after (iota (length before)))
          (check (.ref (cadr before) 'rows) => [])
          (check (.ref (cadr after) 'rows) => '((0)))
          ;; Abandoned preparation does not change the earlier owner.
          (check (eq? snapshot (gerbil-ascent-prepare-source-snapshot snapshot
                                 (source-snapshot-rows snapshot))) => #t))))
    (test-case "rejected acceptance and input failures preserve committed results"
      (let* ((session (gerbil-ascent-open-session (snapshot-program 8 #f)))
             (held (gerbil-ascent-session-run session)))
        (check-exception
         (gerbil-ascent-session-replace-sources! session '((blocked (0))) (lambda (_) #f))
         (failure-message? "ASCENT replacement result was not accepted"))
        (check (eq? held (gerbil-ascent-session-run session)) => #t)
        (check-exception (gerbil-ascent-session-replace-sources! session '((blocked (0 1))))
                         Error?)
        (check (eq? held (gerbil-ascent-session-run session)) => #t)
        (gerbil-ascent-session-replace-sources! session '((blocked (0))))
        (check ((.ref (gerbil-ascent-session-run session) 'rows-of) 'output) => [])
        (check ((.ref held 'rows-of) 'output) => '((0)))
        (gerbil-ascent-session-replace-sources! session '((blocked)))
        (check ((.ref (gerbil-ascent-session-run session) 'rows-of) 'output) => '((0)))))
    (test-case "mutable source spines are rechecked rather than admitted by identity"
      (let* ((program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'input 1 (list (list 0)))) [] 8 8 8))
             (snapshot (gerbil-ascent-source-snapshot program))
             (row (car (vector-ref (source-snapshot-rows snapshot) 0))))
        (set-cdr! row '(1))
        (check-exception (gerbil-ascent-open-session
                          (source-snapshot-program
                           (gerbil-ascent-prepare-source-snapshot snapshot
                             (source-snapshot-rows snapshot))))
                         (failure-message? "invalid ASCENT relation row"))))))
