;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publish the native API through the Yuanxu module role.
(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" InterfaceScopeContract)
        (only-in "./objects.ss" InterfaceAPI))

(export Interface)

(.def Interface
  identity: 'interface
  core:
  (.o
    scope-contract: InterfaceScopeContract
    exports: InterfaceAPI)
  features: (.o))
