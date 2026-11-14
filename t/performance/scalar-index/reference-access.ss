;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Physical index access owned by one engine. Only the canonical built-in
;;; provider has trusted hash buckets; every other receiver keeps dispatch.
(import (only-in :gerbil-ascent/table/funs gerbil-ascent-index-build gerbil-ascent-index-extend!)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider
                 gerbil-ascent-index-provider-build gerbil-ascent-index-provider-extend!
                 gerbil-ascent-index-provider-lookup))
(export gerbil-ascent-physical-index-build gerbil-ascent-physical-index-extend!
        gerbil-ascent-physical-index-rows)

;; : (-> IndexProvider Rows Columns Index)
(def (gerbil-ascent-physical-index-build provider rows columns)
  (if (eq? provider gerbil-ascent-hash-index-provider)
    (gerbil-ascent-index-build rows columns)
    (gerbil-ascent-index-provider-build provider rows columns)))

;; : (-> IndexProvider Index Rows Columns Index)
(def (gerbil-ascent-physical-index-extend! provider index rows columns)
  (if (eq? provider gerbil-ascent-hash-index-provider)
    (gerbil-ascent-index-extend! index rows columns)
    (gerbil-ascent-index-provider-extend! provider index rows columns)))

;; : (-> IndexProvider Index Key Rows)
(def (gerbil-ascent-physical-index-rows provider index key)
  (if (eq? provider gerbil-ascent-hash-index-provider)
    (or (hash-get index key) [])
    (let (matched (gerbil-ascent-index-provider-lookup provider index key))
      (unless (list? matched)
        (error "ASCENT index provider returned non-list rows" matched))
      matched)))
