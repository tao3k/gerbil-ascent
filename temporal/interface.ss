;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Sole Module declaration. Native Scheme exports belong to func.ss.
(import (only-in :gerbil-ascent/candidate/types CandidateScopeContract))
(.def Temporal
  identity: 'temporal
  core: (.o requires: (.o Candidate: (.o module-id: 'candidate contract: CandidateScopeContract))
            scope-contract: TemporalScopeContract
            exports: TemporalAPI)
  features: (.o))
