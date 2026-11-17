;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publish the native API through the Yuanxu module role.
(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ProgramScopeContract)
        (only-in "./objects.ss" ProgramAPI))

(export Program)

(.def Program
  identity: 'program
  core:
  (.o
    scope-contract: ProgramScopeContract
    exports: ProgramAPI)
  features: (.o))
