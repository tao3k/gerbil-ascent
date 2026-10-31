;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/test/base :gerbil/runtime/thread :gerbil/runtime/gambit
        :std/misc/process
        :gerbil-ascent/t/qualification/ascent-candidate-flow-test
        :gerbil-ascent/t/qualification/ascent-candidate-description-test
        :gerbil-ascent/t/qualification/ascent-reasoning-library-test
        :gerbil-ascent/t/qualification/ascent-positive-nonmembership-test
        :gerbil-ascent/t/qualification/ascent-stratified-proof-test)
(export main)
(def (qualify-suite suite)
  ;; Each process owns its mutable std/test tree. Cases retain suite order.
  (test-run! (TestHarness (TestObject-info suite)
               (TestConfig verbosity: 5 capture-output?: #f)
               (list (TestModule (TestObject-info suite) (list suite) [] void void)))))
(def (main (selected #f))
  (let* ((suites (list ascent-candidate-flow-test ascent-candidate-description-test
                      ascent-reasoning-library-test ascent-positive-nonmembership-test
                      ascent-stratified-proof-test)))
    (if selected
      (let (index (string->number selected))
        (unless (and (exact-integer? index) (<= 0 index) (< index (length suites)))
          (error "unknown Candidate qualification suite" selected))
        (unless (test-result-ok? (qualify-suite (list-ref suites index))) (exit 42)))
      (let ((capacity (max 1 (min (##cpu-count) (length suites))))
            (executable (car (command-line))))
        (displayln "CANDIDATE-SUITES processes=" capacity) (force-output)
        ;; Native threads wait on isolated children, including a one-processor VM.
        ;; Join a bounded batch before admitting more work; no mutable tree crosses
        ;; processes and process status propagates through the native API.
        (let loop ((pending (iota (length suites))))
          (unless (null? pending)
            (let* ((count (min capacity (length pending)))
                   (tasks (map (lambda (index)
                                 (spawn run-process/batch
                                   (list executable "-:max-heap=1G,debug=q"
                                         (number->string index))))
                               (take pending count))))
              (for-each thread-join! tasks)
              (loop (drop pending count)))))))
    (displayln "OK") (force-output) (exit 0)))
