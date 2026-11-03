;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Sole Module declaration. Native Scheme exports belong to func.ss.
(.def Core
  identity: 'core
  core:
  (.o
    requires: (.o)
    scope-contract: CoreScopeContract
    exports: CoreAPI)
  features: (.o))
