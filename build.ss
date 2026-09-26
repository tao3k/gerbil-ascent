#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/build-script defbuild-script))

(defbuild-script
  '("table/expression"
    "program/types"
    "program/objects"
    "program/aggregators"
    "program/evaluate"
    "program/interface"
    "core/binary-program"
    "candidate/closure"
    "interface/request"))
