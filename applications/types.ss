;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))
(export ApplicationsScopeContract)
(def ApplicationsOperation (.cc Type. '.element? procedure?))
(def ApplicationsScopeContract
  (.cc YuanxuContract. identity: 'ascent/applications-scope proto: (.o)
       value-contract: (Record finite-flow: (list ApplicationsOperation)
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
                              movie-cast: (list ApplicationsOperation))))
