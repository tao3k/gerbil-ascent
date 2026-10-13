;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Linked development shell. Upstream owns expansion, reload and the REPL.
(import :gerbil/expander :std/interactive
        (for-syntax :gerbil/runtime/system)
        (only-in :gerbil/runtime/init gerbil-load-expander!)
        (only-in :gerbil/runtime/repl replx)
        :gerbil-ascent/program/syntax :gerbil-ascent/program/interface
        :gerbil-ascent/interface/engine-api)
(export main)

;; This local development artifact uses its compiler's syntax metadata. Gambit's
;; ~~ directory can differ for a linked executable from the gxi driver prefix.
(defsyntax (development-library stx)
  (datum->syntax #f (path-expand "lib" (gerbil-home))))

(def (main . args)
  (add-load-path! (development-library))
  (gerbil-load-expander!)
  (eval-syntax '(import :gerbil/core :gerbil/runtime/gambit :std/interactive
                       :gerbil-ascent/program/syntax
                       :gerbil-ascent/program/interface
                       :gerbil-ascent/interface/engine-api))
  (match args
    ([] (replx))
    (["--eval" text]
     (call-with-input-string text
       (lambda (port)
         (let loop ()
           (let (form (read port))
             (unless (eof-object? form)
               (eval-syntax form)
               (loop)))))))
    (else (error "usage: ascent-develop [--eval Scheme-expression]"))))
