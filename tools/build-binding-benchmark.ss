;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/make make))

;;; Both engines and row binders use identical optimizing compilation.
;;; The private output directory also keeps installed candidate artifacts
;;; out of the comparison until the experiment has earned retention.
(make '("core/dependency-graph" "core/rule-semantics" "program/objects" "program/evaluate"
        "t/qualification/ascent-binding-reference-fixture"
        "t/qualification/ascent-binding-reference-evaluate"
        "t/qualification/ascent-index-program-fixture")
      srcdir: (current-directory)
      libdir: (getenv "ASCENT_BINDING_BENCH_LIB")
      build-deps: ".gerbil/binding-benchmark/build-deps")
(exit 0)
