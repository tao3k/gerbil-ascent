;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/make make))

;;; Compile both current planning and the frozen oracle into one isolated
;;; output directory with identical optimizing std/make settings. This avoids
;;; stale installed candidate code and interpreted/compiled timing confounds.
(make '("core/dependency-graph" "core/rule-semantics" "t/qualification/ascent-strata-fixture")
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_STRATA_BENCH_LIB")
      build-deps: ".gerbil/strata-benchmark/build-deps")
(exit 0)
