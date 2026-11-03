;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))

(export TemporalScopeContract)

(def TemporalOperation (.cc Type. '.element? procedure?))

(def TemporalScopeContract
  (.cc YuanxuContract.
    identity: 'ascent/temporal-scope
    proto: (.o)
    value-contract:
    (Record
      lens: (list TemporalOperation)
      source: (list TemporalOperation)
      solve: (list TemporalOperation)
      fork: (list TemporalOperation)
      scope: (list TemporalOperation)
      projection: (list TemporalOperation)
      verify: (list TemporalOperation)
      compare: (list TemporalOperation))))
