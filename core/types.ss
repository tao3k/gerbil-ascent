;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))

(export CoreScopeContract)

(def CoreOperation (.cc Type. '.element? procedure?))

(def CoreScopeContract
  (.cc YuanxuContract.
    identity: 'ascent/core-scope
    proto: (.o)
    value-contract:
    (Record
      finite-flow: (list CoreOperation)
      freeze-masks: (list CoreOperation)
      binary-relation: (list CoreOperation)
      binary-copy: (list CoreOperation)
      binary-filter: (list CoreOperation)
      binary-join: (list CoreOperation)
      evaluate-binary: (list CoreOperation)
      execution-control: (list CoreOperation)
      checkpoint!: (list CoreOperation)
      accept-publication!: (list CoreOperation)
      with-recovery: (list CoreOperation))))
