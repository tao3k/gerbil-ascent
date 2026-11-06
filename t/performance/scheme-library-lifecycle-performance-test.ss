;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One finite specification for the common native/candidate subset.
;;; The matrix below does not call an ASCENT evaluator to obtain expectations.
(import (only-in :std/test test-suite test-case)
        (only-in :gerbil-ascent/t/qualification/scheme-library-contract-fixture sample-lifecycle))
(export scheme-library-lifecycle-performance-test)
(def scheme-library-lifecycle-performance-test
  (test-suite "Matched complete application lifecycle costs"
    (test-case "composed application lifecycle includes initialization and replay costs"
      (for-each
       (lambda (pair)
         (let* ((retained-first? (even? pair))
                (a (sample-lifecycle retained-first?))
                (b (sample-lifecycle (not retained-first?)))
                (retained (if retained-first? a b))
                (fresh (if retained-first? b a)))
           (displayln "APPLICATION-LIFECYCLE pair=" pair
                      " fresh-cpu-us=" (vector-ref fresh 0)
                      " retained-cpu-us=" (vector-ref retained 0)
                      " fresh-wall-us=" (vector-ref fresh 1)
                      " retained-wall-us=" (vector-ref retained 1)
                      " fresh-bytes=" (vector-ref fresh 2)
                      " retained-bytes=" (vector-ref retained 2))
           (force-output)))
       (iota 12)))
))
