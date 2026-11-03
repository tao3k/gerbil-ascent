;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import
  (only-in :clan/poo/object .o)
  "types.ss"
  "func.ss")

(export TableAPI)

(def TableAPI
  (.o
    types:
    (.o
      scope: TableScopeContract
      index-provider: GerbilAscentIndexProviderContract
      storage-provider: GerbilAscentStorageProviderContract)
    hash-index-provider: gerbil-ascent-hash-index-provider
    set-storage-provider: gerbil-ascent-set-storage-provider))
