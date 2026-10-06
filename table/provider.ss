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
        (only-in "funs.ss" gerbil-ascent-index-build
                 gerbil-ascent-index-extend!))

(export GerbilAscentIndexProviderContract
        gerbil-ascent-hash-index-provider
        gerbil-ascent-curried-index-provider
        gerbil-ascent-curried-index-provider?
        gerbil-ascent-canonical-hash-index-provider?
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
;;; Candidates must be proper tuples of the relation's admitted arity. The
;;; engine validates the complete custom lookup batch before matching terms.
;;; Every candidate must also belong to the snapshot supplied to this index;
;;; a delta index cannot return an old total-only fact. Keys may overselect
;;; existing candidates, but indexes cannot introduce new relation facts.
;;; Lookup must include every snapshot row with the requested key, once per
;;; candidate. The engine checks key coverage and duplicate enumeration.
(.defgeneric (gerbil-ascent-index-provider-lookup provider index key)
  slot: .lookup-index)

;;; The default hash provider preserves row buckets in relation order and
;;; remains replaceable at declaration time without changing rule syntax.
(def +canonical-hash-index-provider+
  (validate GerbilAscentIndexProviderContract
            (.o (:: @ IndexProvider.)
                (.build-index gerbil-ascent-index-build)
                (.extend-index! gerbil-ascent-index-extend!)
                (.lookup-index
                 (lambda (index key) (or (hash-get index key) []))))))

(def gerbil-ascent-hash-index-provider +canonical-hash-index-provider+)

;;; Curried sharing is an explicit receiver choice. The ordinary receiver
;;; keeps its measured representation; an engine using this receiver derives
;;; compatible logical requirements and owns its curried roots and adapters.
(def +curried-index-provider+
  (validate GerbilAscentIndexProviderContract
            (.o (:: @ IndexProvider.)
                (.build-index gerbil-ascent-index-build)
                (.extend-index! gerbil-ascent-index-extend!)
                (.lookup-index
                 (lambda (index key) (or (hash-get index key) []))))))
(def gerbil-ascent-curried-index-provider +curried-index-provider+)

;; gerbil-ascent-curried-index-provider?
;; : (-> IndexProviderCandidate Boolean)
;; | doc m%
;;     Admit only the privately retained curried receiver. Inherited receivers
;;     remain custom Providers; mutable physical roots belong to each engine.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-curried-index-provider? gerbil-ascent-curried-index-provider)
;;     ;; => #t
;;     ```
;;   %
(def (gerbil-ascent-curried-index-provider? value)
  (eq? value +curried-index-provider+))

;;; The exported default can be rebound. Native representation admission uses
;;; the private, module-initialized receiver, never a caller's new default.
;; gerbil-ascent-canonical-hash-index-provider?
;;   : (-> IndexProviderCandidate Boolean)
;;   | doc m%
;;       Recognize the privately retained hash receivers validated at module load.
;;       Rebinding the exported default does not grant native representation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-canonical-hash-index-provider? gerbil-ascent-hash-index-provider)
;;       ;; => #t for the original exported default
;;       ```
;;     %
(def (gerbil-ascent-canonical-hash-index-provider? value)
  (or (eq? value +canonical-hash-index-provider+)
      (eq? value +curried-index-provider+)))
