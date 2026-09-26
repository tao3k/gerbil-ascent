;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One receiver axis: a relation index Provider owns physical build and
;;; lookup. Rules remain independent of the provider's private index value.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :poo-flow-foundation/module-system/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in "funs.ss" gerbil-ascent-index-build))

(export GerbilAscentIndexProviderContract
        gerbil-ascent-hash-index-provider
        gerbil-ascent-index-provider-build
        gerbil-ascent-index-provider-lookup)

(def +procedure+
  (poo-flow-predicate-contract 'ascent/index-provider-procedure
                               procedure?
                               (lambda (_value _context) [])))

(define-type (GerbilAscentIndexProviderContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/index-provider
  proto: (.o)
  responsibilities: (.o .build-index: +procedure+
                      .lookup-index: +procedure+))

(def IndexProvider. (.ref GerbilAscentIndexProviderContract 'proto))

(.defgeneric (gerbil-ascent-index-provider-build provider rows columns)
  slot: .build-index)
(.defgeneric (gerbil-ascent-index-provider-lookup provider index key)
  slot: .lookup-index)

(def gerbil-ascent-hash-index-provider
  (validate GerbilAscentIndexProviderContract
            (.o (:: @ IndexProvider.)
                (.build-index gerbil-ascent-index-build)
                (.lookup-index
                 (lambda (index key) (or (hash-get index key) []))))))
