;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/program/interface
        :gerbil-ascent/program/syntax
        :gerbil-ascent/interface/evidence-module)
(export (import: :gerbil-ascent/program/interface)
        (import: :gerbil-ascent/program/syntax)
        ascent-evidence-module define-evidence)

;; Ordinary hygienic Scheme binding: helpers, imports, macros and native
;; Program/Fragment/operator constructors retain their upstream semantics.
(defrules define-evidence ()
  ((_ (constructor argument ...) program explain)
   (def (constructor argument ...) (ascent-evidence-module program explain)))
  ((_ (constructor argument ...) program)
   (def (constructor argument ...) (ascent-evidence-module program))))
