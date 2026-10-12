;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :gerbil/expander import-module)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :gerbil-ascent/program/types GerbilAscentSessionContract)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation gerbil-ascent-program)
        (only-in :gerbil-ascent/t/qualification/ascent-result-reference-evaluate
                 ascent-result-reference-make-engine)
        (only-in :gerbil-ascent/tools/test-modules striped-module-files)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-worker-count testing-interface-test-file-batches))
(export ascent-source-import-test)

(def ascent-source-import-test
  (test-suite "Source fixtures retain the native production module identity"
    (test-case "late source fixture imports preserve existing and future native Sessions"
      (let* ((program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'input 1 '((1)))) [] 8 8 8))
             (prototype (.ref GerbilAscentSessionContract 'proto))
             (held (ascent-result-reference-make-engine program #t)))
        ;; These source fixtures import reference algorithms with production
        ;; dependencies. They must resolve the same Library contexts as the
        ;; native reference loaded above, without reinitializing its namespace.
        (for-each (lambda (path)
          (import-module path #f #t)
          (check-equal? (eq? prototype (.ref GerbilAscentSessionContract 'proto)) #t)
          (check-equal? (eq? held (validate GerbilAscentSessionContract held)) #t)
          (let (fresh (ascent-result-reference-make-engine program #t))
            (check-equal? (eq? fresh (validate GerbilAscentSessionContract fresh)) #t)))
          '("t/qualification/ascent-round-workspace-test.ss"
            "t/qualification/ascent-uf-dense-test.ss"
            "t/qualification/ascent-uf-growth-test.ss"))))
    (test-case "native capacity retains every module and distributes adjacent inputs"
      (let* ((files (list-sort string<?
                      (map (lambda (index) (string-append "module-" (number->string index) "-test.ss"))
                           (iota 37))))
             (workers (testing-interface-worker-count (length files)))
             (batches (testing-interface-test-file-batches (testing-interface)
                        (striped-module-files files workers))))
        (check-equal? (list-sort string<? (apply append batches)) files)
        (check-equal? (length batches) workers)
        (when (> workers 1)
          (check-equal? (and (member (cadr files) (car batches)) #t) #f))))))
