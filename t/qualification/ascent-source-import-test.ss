;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal? check-exception)
        (only-in :gerbil/expander import-module)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/type validate)
        (only-in :gerbil-ascent/program/types GerbilAscentSessionContract)
        (only-in :gerbil-ascent/program/func gerbil-ascent-relation gerbil-ascent-program)
        (only-in :gerbil-ascent/t/qualification/ascent-result-reference-evaluate
                 ascent-result-reference-make-engine)
        (only-in :gerbil-ascent/t/harness/test striped-module-files source-test-interface source-test-batches source-live-ratio source-vm-command single-thread-vm-command preparation-batches-bounded?)
        (only-in :gerbil-ascent/t/harness/library-spec preparation-support-roots)
        (only-in :asp-gerbil-scheme/testing-api testing-interface
                 testing-interface-worker-count testing-interface-test-file-batches
                 testing-interface-test-file-isolated? testing-interface-test-file-serial?
                 testing-interface-runtime-options-for))
(export ascent-source-import-test)

(def isolated-source-fixtures
  '("t/qualification/ascent-aggregate-admission-test.ss"
    "t/qualification/ascent-candidate-flow-test.ss"
    "t/qualification/ascent-delta-admission-test.ss"
    "t/qualification/ascent-operator-publication-test.ss"
    "t/qualification/ascent-semi-naive-test.ss"
    "t/qualification/ascent-value-membership-test.ss"
    "t/qualification/scheme-closure-contract-test.ss"
    "t/qualification/static-link-inputs-test.ss"
    "t/qualification/yuanxu-library-test.ss"))

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
    (test-case "Darwin GC targets preserve hard heaps and isolated work"
      (let (command '("gxi" "-:max-heap=2048M" "-e" "(native-main)" "-v" "5" "suite.ss"))
        (check-equal? (source-live-ratio #t) 90)
        (check-equal? (source-live-ratio #f) 50)
        (check-equal? (source-live-ratio #t parallel-source?: #f) 50)
        (check-equal? (source-live-ratio parallel-source?: #f) 50)
        (for-each (lambda (ratio)
          (let (actual (source-vm-command command ratio))
            (check-equal? (cadr actual)
              (string-append "-:max-heap=2048M,live-ratio=" (number->string ratio)))
            (check-equal? (drop actual 4) (drop command 4))
            (check-equal? (string-suffix? "(native-main)" (list-ref actual 3)) #t))) '(50 90))
        (check-exception (source-vm-command '("gxi" "-e" "(native-main)") 90) true)
        (check-exception (source-vm-command command 80) true)
        (check-exception (source-vm-command command 95) true)
        (check-exception (source-vm-command command 0) true)))
    (test-case "source retention bounds reject oversized batches on both hosts"
      (let (files (map (lambda (i) (string-append "module-" (number->string i))) (iota 17)))
        (check-equal? (preparation-batches-bounded? (list files) 184 12 #f) #f)
        (check-equal? (preparation-batches-bounded? (list (take files 16)) 184 12 #f) #t)
        (check-equal? (preparation-batches-bounded? (list (take files 9)) 184 12 #t) #f)
        (check-equal? (preparation-batches-bounded? (list (take files 8)) 184 12 #t) #t)
        (check-equal? (preparation-batches-bounded? (map list files) 184 12) #t)))
    (test-case "global protocol and build graph effects cannot share another Suite's VM"
      (let* ((profiled (source-test-interface "batched" "2G"))
             (ordinary '("t/qualification/ascent-actor-session-test.ss"
                         "t/qualification/ascent-engine-interface-test.ss"))
             (files (append ordinary isolated-source-fixtures))
             (batches (source-test-batches profiled files "batched")))
        (for-each (lambda (file)
          (check-equal? (testing-interface-test-file-isolated? profiled file) #t)
          (check-equal? (testing-interface-test-file-serial? profiled file)
            (and (member file '("t/qualification/static-link-inputs-test.ss"
                               "t/qualification/yuanxu-library-test.ss")) #t))
          (check-equal? (source-live-ratio #t) 90)
          (check-equal? (filter (lambda (batch) (member file batch)) batches) (list (list file))))
          isolated-source-fixtures)
        (for-each (lambda (file)
          (check-equal? (testing-interface-test-file-isolated? profiled file) #f)) ordinary)
        (check-equal? (list-sort string<? (apply append batches)) (list-sort string<? files))))
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
    (test-case "bounded native batches preserve the complete ordered source projection"
      (for-each (lambda (n)
        (let* ((normal (map (lambda (i) (string-append "module-" (number->string i) "-test.ss")) (iota n)))
               (heavy isolated-source-fixtures)
               (files (list-sort string<? (append heavy normal)))
               (profiled (source-test-interface "batched" "2G"))
               (native (source-test-batches profiled files "batched" #f))
               (bounded (source-test-batches profiled files "batched" #t))
               (workers (testing-interface-worker-count (length files))))
          (check-equal? (apply append bounded) (apply append native))
          (check-equal? (list-sort string<? (apply append bounded)) files)
          (check-equal? (preparation-batches-bounded? bounded (length files) workers #t) #t)
          (check-equal? (preparation-batches-bounded? native (length files) workers #f) #t)
          (when (and (= n 175) (= workers 12))
            (check-equal? (length native) 21)
            (check-equal? (length bounded) 33)
            (check-equal? (drop native (length heavy))
              (testing-interface-test-file-batches profiled
                (striped-module-files (list-sort string<? normal) workers))))))
        '(0 1 11 12 13 143 144 145 172 175 177 182)))
    (test-case "only the two source build projections claim the serial resource"
      (let* ((files (append isolated-source-fixtures
                           '("t/qualification/ascent-actor-session-test.ss"
                             "t/qualification/ascent-source-import-test.ss")))
             (profiled (source-test-interface "batched" "2G"))
             (serial (filter (cut testing-interface-test-file-serial? profiled <>) files)))
        (check-equal? serial '("t/qualification/static-link-inputs-test.ss"
                               "t/qualification/yuanxu-library-test.ss"))
        (for-each (lambda (darwin?)
          (let (batches (source-test-batches profiled files "batched" darwin?))
            (check-equal? (list-sort string<? (apply append batches)) (list-sort string<? files))))
          '(#t #f))))
    (test-case "exhaustive corpora are isolated within unchanged ordinary capacity bounds"
      (let* ((normal (map (lambda (i) (string-append "module-" (number->string i) "-test.ss")) (iota 37)))
             (heavy isolated-source-fixtures)
             (files (list-sort string<? (append heavy normal)))
             (profiled (source-test-interface "batched" "2G"))
             (batches (source-test-batches profiled files "batched" #t))
             (baseline (testing-interface-test-file-batches (testing-interface)
                         (striped-module-files (list-sort string<? normal)
                           (testing-interface-worker-count (length files))))))
        (check-equal? (list-sort string<? (apply append batches)) files)
        ;; The native framework still owns compatibility and order. The
        ;; retained-source bound may split a group, never reorder its entries.
        (check-equal? (apply append batches) (apply append (append (map list heavy) baseline)))
        (for-each (lambda (darwin?)
          (let* ((workers (testing-interface-worker-count (length normal)))
                 (ordinary (drop (source-test-batches profiled files "batched" darwin?) (length heavy)))
                 (bound (min (if darwin? 8 (length normal)) (ceiling (/ (length normal) workers)))))
            (for-each (lambda (batch) (check-equal? (<= (length batch) bound) #t)) ordinary)))
          '(#t #f))
        (for-each (lambda (file)
          (check-equal? (testing-interface-runtime-options-for profiled file)
                        (testing-interface-runtime-options-for profiled (car normal)))) heavy)
        (let (isolated (source-test-batches (source-test-interface "isolated" "2G") files "isolated"))
          (check-equal? isolated (map list files)))))))
