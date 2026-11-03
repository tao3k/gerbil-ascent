;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o) "api.ss")
(export ProgramAPI)
;; Actual Module scope, containing the existing native functions unchanged.
(def ProgramAPI
  (.o types: (.o scope: ProgramScopeContract
                 program: GerbilAscentProgramContract
                 session: GerbilAscentSessionContract)
      relation: gerbil-ascent-relation program: gerbil-ascent-program
      evaluate: gerbil-ascent-evaluate-program
      open-session: gerbil-ascent-open-session solve: relational-solve))
