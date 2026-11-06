;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import
  (only-in :clan/poo/object .o)
  "func.ss")

(export TemporalAPI)

(def TemporalAPI
  (.o
    lens: temporal-lens
    source: temporal-source
    solve: temporal-solve
    fork: temporal-fork
    scope: temporal-scope
    projection: temporal-projection
    verify: temporal-verify
    compare: temporal-compare))
