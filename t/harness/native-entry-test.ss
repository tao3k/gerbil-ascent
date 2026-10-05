;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :std/test/base TestSuite))
(export native-entry-test test-setup! test-cleanup!)

;;; Counterexample controls qualify the test adapter, not production semantics.
(def state 'initial)
(def (control? name) (equal? (getenv "ASCENT_NATIVE_ENTRY_CONTROL" #f) name))
(def (test-setup!)
  (when (control? "setup") (error "native entry setup control"))
  (check-equal? state 'initial)
  (set! state 'ready))
(def (test-cleanup!)
  (check-equal? state 'ready)
  (set! state 'initial)
  (displayln "NATIVE-ENTRY-CLEANUP-OK") (force-output)
  (when (control? "cleanup") (error "native entry cleanup control")))
(def native-entry-test
  (if (control? "empty")
    (TestSuite "Native entry lifecycle" void)
    (test-suite "Native entry lifecycle"
      (test-case "module setup precedes Cases"
        (check-equal? state 'ready))
      (test-case "Case failure preserves native verdict"
        (when (control? "case") (error "native entry Case control"))
        (check-equal? state 'ready)))))
