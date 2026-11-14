;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/type Record)
        (only-in :gerbil-ascent/table/provider GerbilAscentIndexProviderContract)
        (only-in :gerbil-ascent/table/storage GerbilAscentStorageProviderContract))

(export TableScopeContract)

(def TableScopeContract
  (.cc (Record
      hash-index-provider: (list GerbilAscentIndexProviderContract)
      set-storage-provider: (list GerbilAscentStorageProviderContract))
    identity: 'ascent/table-scope))
