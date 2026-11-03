;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Sole Module declaration. Native Scheme exports belong to func.ss.
(import (only-in :gerbil-ascent/program/types ProgramScopeContract))
(.def Candidate
  identity: 'candidate
  core: (.o requires: (.o Program: (.o module-id: 'program contract: ProgramScopeContract))
            scope-contract: CandidateScopeContract
            exports: CandidateAPI)
  features: (.o))
