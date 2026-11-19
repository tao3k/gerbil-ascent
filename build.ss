#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .get .call)
        (only-in :std/source this-source-file)
        (only-in :std/build-script defbuild-script)
        (only-in "./init.ss" gerbil-ascent.init.exports)
        (only-in "./interface/build.ss" Build)
        "./package-spec.ss")
(export (import: "./package-spec.ss"))

(def (main . args)
  (defbuild-script (.get gerbil-ascent.init.exports std-make-spec)
    optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (when (or (null? args) (equal? (car args) "compile"))
    (.call Build .prepare (if (null? args) '() (cdr args))))
  (apply main args))
