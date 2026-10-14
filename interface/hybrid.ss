;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; ASCENT business exports. GC, roots and conversions belong to the upstream bridge.
(import (only-in "engine-api.ss" ascent-engine-call)
        :gerbil-scheme-rust/scheme/runtime)
(export main)
(def (main . _) (void))
(def (failure-message failure)
  ;; SyntaxError display pretty-prints through Gambit's terminal machinery.
  ;; A library error must not require a controlling terminal or enter a REPL.
  (or (error-message failure)
      (with-catch
        (lambda (_) "Scheme operation failed while formatting its exception")
        (lambda ()
          (call-with-output-string (lambda (port) (display-exception failure port)))))))
(def (invoke request)
  (with-catch
    (lambda (failure) (vector #f (failure-message failure)))
    (lambda () (vector #t (ascent-engine-call request)))))
(begin-foreign
  (c-define (invoke request) (int64) int64 "ascent_hybrid_call" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call request
      gerbil-ascent/interface/hybrid#invoke)))
