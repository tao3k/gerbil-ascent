;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One receiver axis: a relation index Provider owns physical build and
;;; lookup. Rules remain independent of the provider's private index value.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :core/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in :gerbil-ascent/t/qualification/ascent-index-reference-funs gerbil-ascent-index-build
                 gerbil-ascent-index-extend!))

(export GerbilAscentIndexProviderContract
        ascent-index-reference-hash-index-provider
        gerbil-ascent-index-provider-build
        gerbil-ascent-index-provider-extend!
        gerbil-ascent-index-provider-lookup)

(def +procedure+
  (poo-flow-predicate-contract 'ascent/index-provider-procedure
                               procedure?
                               (lambda (_value _context) [])))

;;; A provider controls physical lookup but cannot change relation semantics;
;;; build, extend, and lookup slots remain one validated receiver axis.
(define-type (GerbilAscentIndexProviderContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/index-provider
  proto: (.o)
  responsibilities: (.o .build-index: +procedure+
                      .extend-index!: +procedure+
                      .lookup-index: +procedure+))

(def IndexProvider. (.ref GerbilAscentIndexProviderContract 'proto))

;;; Build starts from the evaluator's current immutable row snapshot.
(.defgeneric (gerbil-ascent-index-provider-build provider rows columns)
  slot: .build-index)
;;; Extend receives only newly admitted rows, preserving index cache reuse.
(.defgeneric (gerbil-ascent-index-provider-extend! provider index rows columns)
  slot: .extend-index!)
;;; Lookup is allowed to return a superset of matching rows because an index
;;; covers only selected columns. The evaluator checks every term before a
;;; candidate can contribute to a rule head.
(.defgeneric (gerbil-ascent-index-provider-lookup provider index key)
  slot: .lookup-index)

;;; The default hash provider preserves row buckets in relation order and
;;; remains replaceable at declaration time without changing rule syntax.
(def ascent-index-reference-hash-index-provider
  (validate GerbilAscentIndexProviderContract
            (.o (:: @ IndexProvider.)
                (.build-index gerbil-ascent-index-build)
                (.extend-index! gerbil-ascent-index-extend!)
                (.lookup-index
                 (lambda (index key) (or (hash-get index key) []))))))
