;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publish the native API through the Yuanxu module role.
(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" TemporalScopeContract)
        (only-in "./objects.ss" TemporalAPI))

(export Temporal)

(.def Temporal
  identity: 'temporal
  core:
  (.o
    scope-contract: TemporalScopeContract
    exports: TemporalAPI)
  features: (.o))
