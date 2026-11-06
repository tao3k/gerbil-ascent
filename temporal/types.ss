;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record))

(export TemporalScopeContract)

(def TemporalOperation (.cc Type. '.element? procedure?))

(def TemporalScopeContract
  (.cc (Record
      lens: (list TemporalOperation)
      source: (list TemporalOperation)
      solve: (list TemporalOperation)
      fork: (list TemporalOperation)
      scope: (list TemporalOperation)
      projection: (list TemporalOperation)
      verify: (list TemporalOperation)
      compare: (list TemporalOperation))
    identity: 'ascent/temporal-scope))
