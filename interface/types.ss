;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record))

(export InterfaceScopeContract)

(def InterfaceOperation (.cc Type. '.element? procedure?))

(def InterfaceScopeContract
  (.cc (Record
      dispatch: (list InterfaceOperation)
      program-wire: (list InterfaceOperation)
      call: (list InterfaceOperation))
    identity: 'ascent/interface-scope))
