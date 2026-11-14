;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base :gerbil/runtime/thread :gerbil/runtime/gambit
        :std/misc/process
        :gerbil-ascent/t/qualification/ascent-source-snapshot-test
        :gerbil-ascent/t/qualification/ascent-source-log-test
        :gerbil-ascent/t/qualification/ascent-withdrawal-session-test
        :gerbil-ascent/t/qualification/ascent-timeout-test
        :gerbil-ascent/t/qualification/scheme-session-deletion-test)
(export main)
(def suites
  (list ascent-source-snapshot-test ascent-source-log-test
        ascent-withdrawal-session-test ascent-timeout-test scheme-session-deletion-test))
(def (run-suite suite)
  (test-run! (TestHarness (TestObject-info suite)
    (TestConfig verbosity: 5 capture-output?: #f)
    (list (TestModule (TestObject-info suite) (list suite) [] void void)))))
(def (main (selected #f))
  (if selected
    (let (index (string->number selected))
      (unless (and (exact-integer? index) (<= 0 index) (< index (length suites)))
        (error "unknown source snapshot suite" selected))
      (unless (test-result-ok? (run-suite (list-ref suites index))) (exit 42)))
    (let ((capacity (max 1 (min (##cpu-count) (length suites))))
          (executable (car (command-line))))
      (displayln "SNAPSHOT-SUITES processes=" capacity) (force-output)
      (let loop ((pending (iota (length suites))))
        (unless (null? pending)
          (let* ((count (min capacity (length pending)))
                 (tasks (map (lambda (index)
                               (spawn run-process/batch
                                 (list executable "-:max-heap=1G,debug=q"
                                       (number->string index)))) (take pending count)))
                 (outcomes (map (lambda (task)
                                  (with-catch (lambda (failure)
                                                (display-exception failure) #f)
                                    (lambda () (thread-join! task) #t))) tasks)))
            ;; Drain every child before reporting a failed batch.
            (unless (andmap identity outcomes) (exit 42))
            (loop (drop pending count)))))))
  (displayln "OK") (force-output) (exit 0))
