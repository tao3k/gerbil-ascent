;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))

(export RulesScopeContract)

(def RulesOperation (.cc Type. '.element? procedure?))

(def RulesScopeContract
  (.cc YuanxuContract.
    identity: 'ascent/rules-scope
    proto: (.o)
    value-contract:
    (Record
      program: (list RulesOperation)
      declare: (list RulesOperation)
      recorded-module: (list RulesOperation)
      capacity: (list RulesOperation)
      load-source: (list RulesOperation)
      load-module: (list RulesOperation)
      prepare-source-context!: (list RulesOperation))))
