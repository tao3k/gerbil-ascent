;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-only runtime dependencies. std/make owns their compilation order.
(import (only-in :gerbil/expander current-expander-module-import core-library-module-path? stx-e)
        (only-in :gerbil/compiler/base current-compile-context))
(export call-with-preparation-production-interfaces test-library-base performance-modules performance-contract-files performance-scenario-files preparation-retained-source? preparation-projection-roots preparation-support-roots preparation-stale-compiler-modules)
;; BEGIN GENERATED PREPARATION INTERFACES
;; Gerbil still owns syntax decoding, path normalization, caching and expansion.
(def (call-with-preparation-production-interfaces admitted? library production thunk)
  (let* ((original (current-expander-module-import))
        (entries
          (if admitted?
            (apply append (map
              (lambda (module)
                (let (target (path-expand (string-append "gerbil-ascent/" module ".ssi") library))
                  (if (file-exists? target)
                    (list (cons (path-normalize (string-append module ".ss")) target)
                          (cons (string->symbol (string-append ":gerbil-ascent/" module)) target))
                    [])))
              production))
            []))
         ;; Reverse insertion retains the first matching alias.
         (interfaces (list->hash-table (reverse entries))))
    (parameterize
      ((current-expander-module-import
         (lambda (path reload?)
           (let (entry
                  (and (not reload?) (not (current-compile-context))
                       (let (key (cond ((string? path) (path-normalize path))
                                        ((core-library-module-path? path) (stx-e path))
                                        (else #f)))
                         (and key (hash-get interfaces key)))))
             (original (or entry path) reload?)))))
      (thunk))))
;; END GENERATED PREPARATION INTERFACES

;; BEGIN GENERATED PREPARATION STALE
(def (preparation-stale-compiler-modules current? production requested cached)
  (if current? []
    (filter (lambda (module) (not (member module production)))
            (append requested cached))))
;; END GENERATED PREPARATION STALE

;; BEGIN GENERATED PREPARATION SOURCE
;; Generated from PreparationWork.lean; formal CI compares this region.
(def (preparation-retained-source? source source-suites? source-consumers)
  (and (not (member source source-consumers))
       (or (not source-suites?) (not (string-suffix? "-test.ss" source)))))
;; END GENERATED PREPARATION SOURCE

;; BEGIN GENERATED PREPARATION ROOTS
(def (preparation-projection-roots production modules tests source-consumers production-current?)
  (append (if production-current?
            (filter (lambda (module) (not (member module production))) modules)
            modules)
          tests source-consumers))
(def (preparation-support-roots source-suites? base requested cached)
  (append (if source-suites? [] base) requested cached))
;; END GENERATED PREPARATION ROOTS

(def (performance-scenario-files)
  (let (selected (getenv "ASCENT_SS_SCENARIO" #f))
    (if selected
      (list selected)
      (filter file-exists?
        (map (lambda (name) (string-append "t/scenarios/performance/" name "/scenario.ss"))
          (filter (lambda (name) (not (member name '("ascent-binary-program" "ascent-shortest-candidates"))))
            (list-sort string<? (directory-files "t/scenarios/performance"))))))))
(def performance-modules
  '("t/performance/ascent-scenario-performance-test.ss"
    "t/performance/ascent-binary-program-performance-test.ss"
    "t/performance/ascent-shortest-candidates-performance-test.ss"))
(def (performance-contract-files)
  ;; Allocation contracts require compiled production code. Source semantic
  ;; Suites remain in t/qualification; this compiled-only Case retains its bound.
  '("t/performance/ascent-withdrawal-support-performance-test.ss"
    "t/performance/ascent-uf-plan-performance-test.ss"
    "t/performance/ascent-change-plan-performance-test.ss"
    "t/performance/ascent-source-cut-allocation-test.ss"
     "t/performance/ascent-component-index-performance-test.ss"
     "t/performance/ascent-actor-credit-performance-test.ss"
     "t/performance/ascent-trrel-uf-performance-test.ss"
     "t/performance/ascent-steensgaard-performance-test.ss"
     "t/performance/ascent-relation-view-performance-test.ss"
     "t/performance/scheme-library-lifecycle-performance-test.ss"))

(def test-library-base
  '("t/performance/library" "t/performance/ascent-ss-profile"
                            "t/scenarios/performance/ascent-table-expression/baseline"
                            "t/harness/artifact-admission" "t/model/response-projection"))
