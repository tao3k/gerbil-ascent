;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Sole Module declaration. Native Scheme exports belong to func.ss.

(import (only-in :gerbil-ascent/program/types ProgramScopeContract)
        (only-in :gerbil-ascent/rules/types RulesScopeContract)
        (only-in :gerbil-ascent/candidate/types CandidateScopeContract))

(.def Interface
  identity: 'interface
  core:
  (.o
    requires:
    (.o
      Program:
      (.o
        module-id: 'program
        contract: ProgramScopeContract)
      Rules:
      (.o
        module-id: 'rules
        contract: RulesScopeContract)
      Candidate:
      (.o
        module-id: 'candidate
        contract: CandidateScopeContract))
    scope-contract: InterfaceScopeContract
    exports: InterfaceAPI)
  features: (.o))
