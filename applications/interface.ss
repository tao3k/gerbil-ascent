;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Publish the native API through the Yuanxu module role.
(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ApplicationsScopeContract)
        (only-in "./objects.ss" ApplicationsAPI))

(export Applications)

(.def Applications
  identity: 'applications
  core:
  (.o
    scope-contract: ApplicationsScopeContract
    exports: ApplicationsAPI)
  features: (.o))
