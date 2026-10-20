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
        (only-in :gerbil-ascent/t/harness/test striped-module-files source-test-interface source-test-batches single-thread-vm-command)
        (only-in :gerbil-ascent/t/harness/library-spec preparation-support-roots)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-worker-count testing-interface-test-file-batches
                 testing-interface-runtime-options-for))
(export ascent-source-import-test)

(def ascent-source-import-test
  (test-suite "Source fixtures retain the native production module identity"
    (test-case "source support follows demand and refreshes cached fixtures"
      (check-equal? (preparation-support-roots #t '("unrelated-driver") '("requested") '("cached"))
                    '("requested" "cached"))
      (check-equal? (preparation-support-roots #f '("base") '("requested") '("cached"))
                    '("base" "requested" "cached")))
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
    (test-case "single-processor assertion preserves native argv and test arguments"
      (let* ((command '("gxi" "-:max-heap=2048M" "-e" "(native-main)" "-v" "5" "suite.ss"))
             (wrapped (single-thread-vm-command command)))
        (check-equal? (length wrapped) (length command))
        (check-equal? (take wrapped 3) (take command 3))
        (check-equal? (drop wrapped 4) (drop command 4))
        (check-equal? (string-suffix? "(native-main)" (list-ref wrapped 3)) #t)))
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
          (check-equal? (and (member (cadr files) (car batches)) #t) #f))))
    (test-case "exhaustive corpora are isolated without dropping or resizing other work"
      (let* ((normal (map (lambda (i) (string-append "module-" (number->string i) "-test.ss")) (iota 37)))
             (heavy '("t/qualification/ascent-candidate-flow-test.ss"
                      "t/qualification/ascent-semi-naive-test.ss"))
             (files (list-sort string<? (append heavy normal)))
             (profiled (source-test-interface "batched" "2G"))
             (batches (source-test-batches profiled files "batched"))
             (baseline (testing-interface-test-file-batches (testing-interface)
                         (striped-module-files (list-sort string<? normal)
                           (testing-interface-worker-count (length files))))))
        (check-equal? (list-sort string<? (apply append batches)) files)
        ;; The independent exhaustive jobs must start before ordinary stripes.
        ;; Otherwise the original deadline can expire before either gets CPU.
        (check-equal? batches (append (map list heavy) baseline))
        (let* ((workers (testing-interface-worker-count (length normal)))
               (ordinary (cddr batches))
               (bound (ceiling (/ (length normal) workers))))
          (check-equal? (<= (length ordinary) workers) #t)
          (for-each (lambda (batch) (check-equal? (<= (length batch) bound) #t)) ordinary))
        (check-equal? (list (car batches) (cadr batches)) (map list heavy))
        (for-each (lambda (file)
          (check-equal? (testing-interface-runtime-options-for profiled file)
                        (testing-interface-runtime-options-for profiled (car normal)))) heavy)
        (let (isolated (source-test-batches (source-test-interface "isolated" "2G") files "isolated"))
          (check-equal? isolated (map list files)))))))
