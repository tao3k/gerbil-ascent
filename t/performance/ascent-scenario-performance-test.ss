;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite)
        (only-in :std/test/base TestCase test-case-add!)
        (only-in :gerbil-ascent/t/harness/library-spec performance-scenario-files)
        (only-in :gerbil-ascent/t/performance/library assert-native-library!))
(export ascent-scenario-performance-test)
(def ascent-scenario-performance-test
  (test-suite "ASCENT SS scenarios"
    (for-each (lambda (path)
      (test-case-add! (TestCase path (lambda ()
        (unless (file-exists? path) (error "missing SS scenario" path))
        (assert-native-library!)
        ;; The original scenario owns its benchmark profile, samples and truth.
        (load path)))))
      (performance-scenario-files))))
