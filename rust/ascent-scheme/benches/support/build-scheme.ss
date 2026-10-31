;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/compiler :std/make)
(def library (path-expand "lib" (gerbil-path)))
(make ["rust/ascent-scheme/benches/support/scheme-runtime"] srcdir: (current-directory) libdir: library
      build-deps: ".cache/ascent/rust-rayon/scheme-build-deps" optimize: #t)
(compile-exe "rust/ascent-scheme/benches/support/scheme-runtime.ss"
             [output-dir: library output-file: ".cache/ascent/rust-rayon/scheme-runtime" invoke-gsc: #t static: #t])
(execute-pending-compile-jobs!)
