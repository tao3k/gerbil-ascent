#!/usr/bin/env gxi
(import (only-in :clan/poo/object .get)
        (only-in :std/source this-source-file)
        (only-in :std/build-script defbuild-script)
        (only-in :tao3k/yuanxu/module-system/building/build-script defmodule-build-script)
        "./package-spec.ss")
(export (import: "./package-spec.ss"))

(defmodule-build-script
  (defbuild-script (.get gerbil-ascent.package.exports std-make-spec)
    optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0")))
  (.get gerbil-ascent.package.exports build-actions))
