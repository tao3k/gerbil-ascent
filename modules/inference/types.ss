;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))
(export ScopeContract)
;; Module admission checks callable publication; behavioral obligations remain tests.
(def Operation (.cc Type. sexp: 'NativeOperation '.element? procedure?))
(def ScopeContract
  (.cc YuanxuContract. identity: 'ascent/inference
       proto: (.o)
       value-contract: (Record relation: (list Operation)
                              program: (list Operation)
                              evaluate: (list Operation)
                              open-session: (list Operation))))
