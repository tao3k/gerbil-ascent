;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-invalid-program-output
                 category))

(export ascent-invalid-program-test)

(def ascent-invalid-program-test
  (test-suite "ASCENT invalid program admission"
    (poo-flow-test-case "dependency and safety errors have distinct causes"
      (for-each
       (lambda (name expected)
         (check-equal? (category name) expected))
       '(lattice-projection-feedback negative-self mutual-negation negative-feedback
                       aggregate-self negative-with-unrelated-aggregate
                       unsafe-negation unbound-head unknown-relation
                       atom-arity duplicate-relation unbound-guard
                       head-arity unbound-let-input unbound-for-input
                       unknown-aggregate-relation negation-before-binding)
       '(lattice-projection-cycle negation-cycle negation-cycle negation-cycle
                        aggregate-cycle negation-cycle
                        unsafe-negation unbound-head unknown-relation
                        atom-arity duplicate-relation unbound-guard
                        atom-arity unbound-clause unbound-clause
                        unknown-relation unsafe-negation)))))
