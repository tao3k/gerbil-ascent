;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A storage Provider changes which facts a relation exposes. The pure
;;; algorithms live in funs.ss; this module owns the POO extension boundary.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :poo-flow-foundation/module-system/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in "funs.ss" gerbil-ascent-eqrel-extension
                 gerbil-ascent-trrel-extension))

(export GerbilAscentStorageProviderContract
        gerbil-ascent-set-storage-provider
        gerbil-ascent-eqrel-storage-provider
        gerbil-ascent-trrel-storage-provider
        gerbil-ascent-storage-extend)

(def +extend+
  (poo-flow-predicate-contract 'ascent/storage-extend procedure?
                               (lambda (_value _context) [])))

(define-type (GerbilAscentStorageProviderContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/storage-provider
  proto: (.o)
  responsibilities: (.o .extend-rows: +extend+))

(def StorageProvider. (.ref GerbilAscentStorageProviderContract 'proto))

(.defgeneric (gerbil-ascent-storage-extend provider all pending row budget)
  slot: .extend-rows)

(def gerbil-ascent-set-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ StorageProvider.)
                (.extend-rows
                 (lambda (_all _pending row _budget) (list row))))))

(def gerbil-ascent-eqrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.extend-rows gerbil-ascent-eqrel-extension))))

(def gerbil-ascent-trrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.extend-rows gerbil-ascent-trrel-extension))))
