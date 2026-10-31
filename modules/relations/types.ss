;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/type Record)
        (only-in :gerbil-ascent/table/interface
                 GerbilAscentIndexProviderContract GerbilAscentStorageProviderContract)
        (only-in :yuanxu/object-types/contracts YuanxuContract.))
(export ScopeContract)
;; Providers are native POO objects with their existing behavioral contracts.
(def ScopeContract
  (.cc YuanxuContract. identity: 'ascent/relations
       proto: (.o)
       value-contract:
       (Record hash-index-provider: (list GerbilAscentIndexProviderContract)
               set-storage-provider: (list GerbilAscentStorageProviderContract))))
