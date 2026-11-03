;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))

(export InterfaceScopeContract)

(def InterfaceOperation (.cc Type. '.element? procedure?))

(def InterfaceScopeContract
  (.cc YuanxuContract.
    identity: 'ascent/interface-scope
    proto: (.o)
    value-contract:
    (Record
      dispatch: (list InterfaceOperation)
      program-wire: (list InterfaceOperation)
      call: (list InterfaceOperation))))
