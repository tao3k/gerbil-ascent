;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Each message names a real import boundary. No timer emits progress.
(when (getenv "ASCENT_TEST_LIBRARY" #f)
  (eval '(import (only-in :gerbil-ascent/t/performance/native-library assert-native-library!)))
  (eval '(assert-native-library!)))
(for-each
 (lambda (module)
   (displayln "IMPORT " module) (force-output)
   (eval `(import ,module))
   (displayln "IMPORT-OK " module) (force-output))
 '(
   :gerbil-ascent/table/expression
   :gerbil-ascent/table/funs
   :gerbil-ascent/table/eqrel
   :gerbil-ascent/table/trrel
   :gerbil-ascent/table/provider
   :gerbil-ascent/table/storage
   :gerbil-ascent/table/interface
   :gerbil-ascent/program/types
   :gerbil-ascent/program/objects
   :gerbil-ascent/program/aggregators
   :gerbil-ascent/program/syntax
   :gerbil-ascent/program/planning
   :gerbil-ascent/program/scheme-checked
   :gerbil-ascent/program/scheme-admission
   :gerbil-ascent/program/scheme-language
   :gerbil-ascent/program/operator
   :gerbil-ascent/program/operator-change
   :gerbil-ascent/program/operator-session
   :gerbil-ascent/core/rule-semantics
   :gerbil-ascent/program/analysis
   :gerbil-ascent/program/summary
   :gerbil-ascent/program/evaluate
   :gerbil-ascent/program/session
   :gerbil-ascent/program/interface
   :gerbil-ascent/core/binary-program
   :gerbil-ascent/candidate/closure
   :gerbil-ascent/candidate/types
   :gerbil-ascent/candidate/program
   :gerbil-ascent/candidate/funs
   :gerbil-ascent/candidate/provenance
   :gerbil-ascent/candidate/nonmembership
   :gerbil-ascent/candidate/finite-evidence
   :gerbil-ascent/candidate/stratified-proof
   :gerbil-ascent/candidate/stratified-producer
   :gerbil-ascent/candidate/reasoning
   :gerbil-ascent/temporal/lens
   :gerbil-ascent/interface/request
   :gerbil/tools/gxtest))
(eval `(exit (gerbil/tools/gxtest#main "-v" "5" ,(getenv "ASCENT_TEMPORAL_TEST_MODULE" "t/qualification/ascent-temporal-lens-test.ss"))))
