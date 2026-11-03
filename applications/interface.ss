;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Sole Module declaration. Native Scheme exports belong to func.ss.
(import (only-in :gerbil-ascent/core/types CoreScopeContract)
        (only-in :gerbil-ascent/program/types ProgramScopeContract))
(.def Applications
  identity: 'applications
  core: (.o requires: (.o Core: (.o module-id: 'core contract: CoreScopeContract)
                             Program: (.o module-id: 'program contract: ProgramScopeContract))
            scope-contract: ApplicationsScopeContract
            exports: ApplicationsAPI)
  features: (.o))
