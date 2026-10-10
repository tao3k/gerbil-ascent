;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite)
        (only-in :std/test/base TestCase test-case-add!)
        (only-in :gerbil-ascent/t/performance/native-library assert-native-library!))
(export ascent-scenario-performance-test)
(def (scenario-paths)
  (let (selected (getenv "ASCENT_SS_SCENARIO" #f))
    (if selected
      (list selected)
      (filter file-exists?
        (map (lambda (name) (string-append "t/scenarios/performance/" name "/scenario.ss"))
          (filter (lambda (name) (not (member name '("ascent-binary-program" "ascent-shortest-candidates"))))
            (list-sort string<? (directory-files "t/scenarios/performance"))))))))
(def ascent-scenario-performance-test
  (test-suite "ASCENT SS scenarios"
    (for-each (lambda (path)
      (test-case-add! (TestCase path (lambda ()
        (unless (file-exists? path) (error "missing SS scenario" path))
        (assert-native-library!)
        ;; The original scenario owns its benchmark profile, samples and truth.
        (load path)))))
      (scenario-paths))))
