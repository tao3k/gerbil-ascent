;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal? check-exception)
        (only-in :gerbil/expander import-module)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :gerbil-ascent/program/types GerbilAscentSessionContract)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation gerbil-ascent-program)
        (only-in :gerbil-ascent/t/qualification/ascent-result-reference-evaluate
                 ascent-result-reference-make-engine)
        (only-in :gerbil-ascent/t/harness/test striped-module-files source-test-interface source-test-batches source-live-ratio source-vm-command single-thread-vm-command preparation-batches-bounded?)
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
    (test-case "linked source VM preserves heap native GxTest argv and processor assertion"
      (let* ((command '("gxi" "-:max-heap=2048M" "-e" "(native-main)" "-v" "5" "suite.ss"))
             (linked (source-vm-command command "/package/bin/ascent-develop")))
        (check-equal? (take linked 3) '("/package/bin/ascent-develop" "-:max-heap=2048M" "--eval-plain"))
        (check-equal? (drop linked 3) (drop (single-thread-vm-command command) 3))
        (check-equal? (source-vm-command command #f) (single-thread-vm-command command))))
    (test-case "ordinary Darwin GC targets preserve hard heaps and isolated work"
      (let* ((profiled (source-test-interface "batched" "2G"))
             (ordinary "t/qualification/scheme-relational-test.ss")
             (heavy "t/qualification/ascent-semi-naive-test.ss")
             (command '("gxi" "-:max-heap=2048M" "-e" "(native-main)" "-v" "5" "suite.ss")))
        (check-equal? (source-live-ratio profiled ordinary #t) 80)
        (check-equal? (source-live-ratio profiled heavy #t) 50)
        (check-equal? (source-live-ratio profiled ordinary #f) 50)
        (check-equal? (source-live-ratio profiled heavy #f) 50)
        (for-each (lambda (ratio)
          (let (actual (source-vm-command command #f ratio))
            (check-equal? (cadr actual)
              (string-append "-:max-heap=2048M,live-ratio=" (number->string ratio)))
            (check-equal? (drop actual 4) (drop command 4))
            (check-equal? (string-suffix? "(native-main)" (list-ref actual 3)) #t))) '(50 80))
        (check-exception (source-vm-command '("gxi" "-e" "(native-main)") #f 80) true)
        (check-exception (source-vm-command command #f 0) true)))
    (test-case "observed wide source batches are rejected before child admission"
      (let (files (map (lambda (i) (string-append "module-" (number->string i))) (iota 15)))
        (check-equal? (preparation-batches-bounded? (list files) 174 12) #f)
        (check-equal? (preparation-batches-bounded? (map list files) 174 12) #t)))
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
    (test-case "bounded packing uses the admitted width without extra twelve-way splits"
      (for-each (lambda (n)
        (let* ((normal (map (lambda (i) (string-append "module-" (number->string i) "-test.ss")) (iota n)))
               (heavy '("t/qualification/ascent-candidate-flow-test.ss"
                        "t/qualification/ascent-semi-naive-test.ss"))
               (files (list-sort string<? (append heavy normal)))
               (profiled (source-test-interface "batched" "2G"))
               (batches (source-test-batches profiled files "batched" #t))
               (workers (testing-interface-worker-count (length files))))
          (check-equal? (list-sort string<? (apply append batches)) files)
          (check-equal? (preparation-batches-bounded? batches (length files) workers) #t)
          (let* ((early (source-test-batches profiled files "batched" #f))
                 (ordinary (cddr early))
                 (warmup (min (length ordinary) workers)))
            (check-equal? batches (append (take ordinary warmup) (map list heavy) (drop ordinary warmup))))
          (when (and (= n 172) (= workers 12))
            (check-equal? (length batches) 90)
            (let (outer (testing-interface-test-file-batches profiled
                         (striped-module-files normal workers)))
              (check-equal? (+ 2 (length (apply append
                (map (cut testing-interface-test-file-batches profiled <>) outer)))) 146)))))
        '(0 1 11 12 13 143 144 145 172)))
    (test-case "both host queue policies preserve every native batch and its resource bound"
      (let* ((normal (map (lambda (i) (string-append "module-" (number->string i) "-test.ss")) (iota 172)))
             (heavy '("t/qualification/ascent-candidate-flow-test.ss"
                      "t/qualification/ascent-semi-naive-test.ss"))
             (files (list-sort string<? (append heavy normal)))
             (profiled (source-test-interface "batched" "2G"))
             (staged (source-test-batches profiled files "batched" #t))
             (early (source-test-batches profiled files "batched" #f))
             (ordinary (cddr early))
             (workers (testing-interface-worker-count (length files))))
        (check-equal? early (append (map list heavy) ordinary))
        (let (warmup (min (length ordinary) workers))
          (check-equal? staged (append (take ordinary warmup) (map list heavy) (drop ordinary warmup))))
        (for-each (lambda (batches)
          (check-equal? (length batches) (length staged))
          (when (= workers 12) (check-equal? (length batches) 90))
          (check-equal? (list-sort string<? (apply append batches)) files)
          (check-equal? (preparation-batches-bounded? batches 174 workers) #t)) (list early staged))
        (check-equal? (source-test-batches profiled files "batched")
                      (cond-expand (darwin staged) (else early)))))
    (test-case "exhaustive corpora are isolated without dropping or resizing other work"
      (let* ((normal (map (lambda (i) (string-append "module-" (number->string i) "-test.ss")) (iota 37)))
             (heavy '("t/qualification/ascent-candidate-flow-test.ss"
                      "t/qualification/ascent-semi-naive-test.ss"))
             (files (list-sort string<? (append heavy normal)))
             (profiled (source-test-interface "batched" "2G"))
             (batches (source-test-batches profiled files "batched" #t))
             (baseline (testing-interface-test-file-batches (testing-interface)
                         (striped-module-files (list-sort string<? normal)
                           (testing-interface-worker-count (length files))))))
        (check-equal? (list-sort string<? (apply append batches)) files)
        ;; Preserve every ordinary batch and isolated corpus, changing only order.
        (let* ((ordinary (apply append (map (cut testing-interface-test-file-batches profiled <>) baseline)))
               (warmup (min (length ordinary) (testing-interface-worker-count (length files)))))
          (check-equal? batches (append (take ordinary warmup) (map list heavy) (drop ordinary warmup))))
        (let* ((workers (testing-interface-worker-count (length normal)))
               (ordinary (cddr (source-test-batches profiled files "batched" #f)))
               (bound (ceiling (/ (length normal) (* workers workers)))))
          (check-equal? (<= (length ordinary) (* workers workers)) #t)
          (for-each (lambda (batch) (check-equal? (<= (length batch) bound) #t)) ordinary))
        (for-each (lambda (file)
          (check-equal? (testing-interface-runtime-options-for profiled file)
                        (testing-interface-runtime-options-for profiled (car normal)))) heavy)
        (let (isolated (source-test-batches (source-test-interface "isolated" "2G") files "isolated"))
          (check-equal? isolated (map list files)))))))
