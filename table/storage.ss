;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A storage Provider changes which facts a relation exposes. Evaluation-local
;;; state belongs to the relation run, not the shared Provider declaration.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :core/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in "eqrel.ss" gerbil-ascent-eqrel-state
                 gerbil-ascent-eqrel-extension)
        (only-in "funs.ss" gerbil-ascent-trrel-extension
                 gerbil-ascent-trrel-uf-extension))

(export GerbilAscentStorageProviderContract
        gerbil-ascent-set-storage-provider
        gerbil-ascent-eqrel-storage-provider
        gerbil-ascent-trrel-storage-provider
        gerbil-ascent-trrel-uf-storage-provider
        gerbil-ascent-storage-make-state
        gerbil-ascent-storage-extend)

(def +make-state+
  (poo-flow-predicate-contract 'ascent/storage-make-state procedure?
                               (lambda (_value _context) [])))
(def +extend+
  (poo-flow-predicate-contract 'ascent/storage-extend procedure?
                               (lambda (_value _context) [])))

(define-type (GerbilAscentStorageProviderContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/storage-provider
  proto: (.o)
  responsibilities: (.o .make-state: +make-state+
                      .extend-rows: +extend+))

(def StorageProvider. (.ref GerbilAscentStorageProviderContract 'proto))

(.defgeneric (gerbil-ascent-storage-make-state provider)
  slot: .make-state)

(.defgeneric (gerbil-ascent-storage-extend provider state all pending row budget)
  slot: .extend-rows)

(def gerbil-ascent-set-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ StorageProvider.)
                (.make-state (lambda () #f))
                (.extend-rows
                 (lambda (_state _all _pending row _budget) (list row))))))

(def gerbil-ascent-eqrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-eqrel-state)
                (.extend-rows gerbil-ascent-eqrel-extension))))

(def gerbil-ascent-trrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.extend-rows
                 (lambda (_state all pending row budget)
                   (gerbil-ascent-trrel-extension all pending row budget))))))

(def gerbil-ascent-trrel-uf-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.extend-rows
                 (lambda (_state all pending row budget)
                   (gerbil-ascent-trrel-uf-extension
                    all pending row budget))))))
