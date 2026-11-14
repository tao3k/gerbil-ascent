;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-invalid-program-output
                 category))

(export ascent-invalid-program-test)

(def ascent-invalid-program-test
  (test-suite "ASCENT invalid program admission"
    (test-case "dependency and safety errors have distinct causes"
      (for-each
       (lambda (name expected)
         (check-equal? (category name) expected))
       '(source-row-arity source-field-type derived-field-type
                           lattice-projection-feedback negative-self
                           mutual-negation negative-feedback
                       aggregate-self negative-with-unrelated-aggregate
                       unsafe-negation unbound-head unknown-relation
                       unknown-negated-relation
                       atom-arity duplicate-relation unbound-guard
                       head-arity unbound-let-input unbound-for-input
                       unbound-aggregate-input aggregate-two-relation-cycle
                       unknown-aggregate-relation negation-before-binding
                       unknown-head-relation negation-arity aggregate-arity
                       unbound-head-expression unbound-atom-expression
                       let-shadows-atom for-shadows-atom
                       aggregate-shadows-atom)
       '(source-row-arity field-type field-type
                    lattice-projection-cycle negation-cycle negation-cycle negation-cycle
                        aggregate-cycle negation-cycle
                        unsafe-negation unbound-head unknown-relation
                        unknown-relation
                        atom-arity duplicate-relation unbound-guard
                        atom-arity unbound-clause unbound-clause
                        unbound-clause aggregate-cycle
                        unknown-relation unsafe-negation
                        unknown-relation atom-arity atom-arity
                        unbound-head unbound-clause
                        variable-shadowing variable-shadowing
                        variable-shadowing)))))
