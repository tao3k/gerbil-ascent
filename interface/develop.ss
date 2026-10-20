;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Linked development shell. Upstream owns expansion, reload and the REPL.
(import :gerbil/expander :std/interactive
        ;; Link the released test runtime once; Suite carriers remain source.
        ;; Every fresh VM can share these read-only image pages instead of
        ;; loading and retiring the same dynamic SDK bundles per batch.
        (only-in :gerbil/tools/gxtest)
        (only-in :std/test)
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

(def (evaluate text)
  (call-with-input-string text
    (lambda (port)
      (let loop ()
        (let (form (read port))
          (unless (eof-object? form)
            (eval-syntax form)
            (loop)))))))

(def (main . args)
  (add-load-path! (development-library))
  (gerbil-load-expander!)
  (eval-syntax '(import :gerbil/core :gerbil/runtime/gambit))
  (match args
    ;; GxTest imports exactly its own source graph. Do not expand application
    ;; REPL conveniences into every test VM before its actual module selection.
    (["--eval-plain" text . arguments] (evaluate text))
    (else
     (eval-syntax '(import :std/interactive
                          :gerbil-ascent/program/syntax
                          :gerbil-ascent/program/interface
                          :gerbil-ascent/interface/engine-api))
     (match args
       ([] (replx))
       (["--eval" text . arguments] (evaluate text))
       (else (error "usage: ascent-develop [--eval Scheme-expression [arguments ...]]"))))))
