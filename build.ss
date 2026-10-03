#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/build-script defbuild-script)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))

(def gerbil-ascent-library-modules
  '("table/expression"
    "table/funs"
    "table/eqrel"
    "table/trrel"
    "table/provider"
    "table/storage"
    "table/interface"
    "program/types"
    "program/objects"
    "program/aggregators"
    "program/syntax"
    "program/planning"
    "program/positive"
    "program/scheme-checked"
    "program/scheme-admission"
    "program/scheme-language"
    "program/operator"
    "program/operator-change"
    "program/operator-session"
    "program/graph"
    "program/funs"
    "program/analysis"
    "program/summary"
    "program/admission"
    "program/evaluate"
    "program/session"
    "program/interface"
    "core/binary-program"
    "candidate/closure"
    "candidate/types"
    "candidate/program"
    "candidate/funs"
    "candidate/provenance"
    "candidate/nonmembership"
    "candidate/finite-evidence"
    "candidate/stratified-proof"
    "candidate/stratified-producer"
    "candidate/reasoning"
    "interface/request"))

(asp-gerbil-scheme-package-spec!
 (gerbil-ascent-library-package-spec
  @ asp-gerbil-scheme-library-package-prototype)
 (spec gerbil-ascent-build-spec)
 (modules gerbil-ascent-library-modules))

(defbuild-script (gerbil-ascent-build-spec))
