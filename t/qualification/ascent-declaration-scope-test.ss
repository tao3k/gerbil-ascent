;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? test-case))
(export ascent-declaration-scope-test)
(include "ascent-declaration-scope-fixture.ss")

(def (check-fixture kind width heads)
  (let-values (((program expected names) (ascent-scope-fixture kind width heads)))
    (let (result (gerbil-ascent-evaluate-program program))
      (for-each
       (lambda (name) (check-equal? ((.ref result 'rows-of) name) (list expected)))
       names))))

(def ascent-declaration-scope-test
  (test-suite "ASCENT declaration name scopes"
    (test-case "multi-head wide declarations retain false values and ordered columns"
      (for-each (lambda (width) (check-fixture 'atom width 8)) '(31 32 33 128)))
    (test-case "wide tuple generator outputs remain available to every head"
      (for-each (lambda (width) (check-fixture 'generator width 2)) '(31 32 33 128)))
    (test-case "wide aggregate inputs and outputs remain separate scopes"
      (for-each (lambda (width) (check-fixture 'aggregate width 2)) '(31 32 33 128)))
    (test-case "pattern and expression scopes preserve callback results"
      (for-each (lambda (width)
                  (check-fixture 'pattern width 2)
                  (check-fixture 'expression width 2)) '(31 32 33 128)))))
