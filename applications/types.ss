;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record))

(export ApplicationsScopeContract)

(def ApplicationsOperation (.cc Type. '.element? procedure?))

(def ApplicationsScopeContract
  (.cc (Record
      finite-flow: (list ApplicationsOperation)
      polonius: (list ApplicationsOperation)
      polonius-paths: (list ApplicationsOperation)
      steensgaard: (list ApplicationsOperation)
      taint-paths: (list ApplicationsOperation)
      scoped-witness: (list ApplicationsOperation)
      branch-scoped-witness: (list ApplicationsOperation)
      scoped-mask: (list ApplicationsOperation)
      bounded-scoped-mask: (list ApplicationsOperation)
      scoped-composition: (list ApplicationsOperation)
      compose-scoped: (list ApplicationsOperation)
      scoped-query: (list ApplicationsOperation)
      movie-cast: (list ApplicationsOperation))
    identity: 'ascent/applications-scope))
