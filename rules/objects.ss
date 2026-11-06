;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import
  (only-in :clan/poo/object .o)
  "declaration.ss"
  "source.ss"
  "module.ss")

(export RulesAPI)

(def RulesAPI
  (.o
    program: ascent-rule-module
    declare: make-declared-program
    recorded-module: make-recorded-module
    capacity: source-capacity
    load-source: ascent-load-module-source
    load-module: ascent-load-rule-module
    prepare-source-context!: ascent-prepare-source-context!))
