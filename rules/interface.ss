;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publish the native API through the Yuanxu module role.
(import (only-in :clan/poo/object .o)
        (only-in :tao3k/yuanxu/module-system/source/declaration .def))

(.def Rules
  identity: 'rules
  core:
  (.o
    scope-contract: RulesScopeContract
    exports: RulesAPI)
  features: (.o))
