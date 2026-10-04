#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/build-script defbuild-script)
        (only-in :std/source this-source-file)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))

(def gerbil-ascent-library-modules
  '("table/expression"
    "table/funs"
    "table/eqrel"
    "table/trrel"
    "table/provider"
    "table/access"
    "table/storage"
    "table/interface"
    "program/types"
    "program/objects"
    "program/aggregators"
    "program/syntax"
    "program/planning"
    "core/positive-plan"
    "program/scheme-checked"
    "program/scheme-admission"
    "program/scheme-language"
    "program/operator"
    "program/higher-order"
    "program/operator-change"
    "program/operator-session"
    "core/dependency-graph"
    "core/rule-semantics"
    "program/analysis"
    "program/summary"
    "program/admission"
    "program/result"
    "program/update-selection"
    "program/reuse"
    "program/evaluate"
    "program/session"
    "program/interface"
    "core/binary-program"
    "candidate/closure"
    "candidate/types"
    "candidate/program"
    "candidate/funs"
    "candidate/provenance"
    "candidate/provenance-graph"
   "candidate/stratified-provenance"
    "candidate/nonmembership"
    "candidate/finite-evidence"
    "candidate/stratified-proof"
    "candidate/stratified-producer"
    "candidate/reasoning"
    "temporal/lens"
    "interface/request"))

(asp-gerbil-scheme-package-spec!
 (gerbil-ascent-library-package-spec
  @ asp-gerbil-scheme-library-package-prototype)
 (spec gerbil-ascent-build-spec)
 (modules gerbil-ascent-library-modules))
(export gerbil-ascent-library-modules)
(defbuild-script (gerbil-ascent-build-spec))
