;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil-ascent/program/operator-analysis
                 capture-operator-transform operator-snapshot-transform operator-snapshot-checked-rows
                 analyze-operator-graph operator-analysis-checked-rows)
        :gerbil-ascent/program/operator
        :gerbil-ascent/program/operator-change)
(export ascent-delta-admission-test)

(def (reject-change transform)
  (let (measured
        (relational-op-measure
         (lambda ()
           (check-exception
            (relational-op-delta-change transform '((0)) '((1)))
            (lambda (_) #t)))))
    (check-equal? (relational-op-measurement-join-probes measured) 0)
    (check-equal? (relational-op-measurement-fix-body-evaluations measured) 0)))

(def ascent-delta-admission-test
  (test-suite "Insertion descriptor admission"
    (test-case "mutated mapping values reject even on empty input"
      (let* ((node #f)
             (transform (relational-op-function 1 (lambda (p)
                          (set! node (relational-op-flatmap p 1 '(((0) (a)))))
                          node))))
        (vector-set! (relational-op-data node) 1 '((0 (mutable))))
        (reject-change transform)
        (check-exception (relational-op-delta-change transform [] []) (lambda (_) #t))))
    (test-case "captured source arity and selection values are rechecked"
      (let* ((source (relational-op-source 'captured 1 '((a))))
             (transform (relational-op-function 1 (lambda (p) (relational-op-union p source)))))
        (vector-set! (relational-op-data source) 1 '((a b)))
        (reject-change transform))
      (let* ((node #f)
             (transform (relational-op-function 1 (lambda (p)
                          (set! node (relational-op-select-eq p 0 0)) node))))
        (vector-set! (relational-op-data node) 1 (lambda (_) #t))
        (reject-change transform)))
    (test-case "pointer cycles reject before recursive evaluation"
      (let* ((node #f)
             (transform (relational-op-function 1 (lambda (p)
                          (set! node (relational-op-project p '(0))) node))))
        (set-car! (relational-op-inputs node) node)
        (reject-change transform)))
    (test-case "shared parameter cannot escape another transformer"
      (let* ((foreign #f)
             (_owner (relational-op-function 1 (lambda (p) (set! foreign p) p)))
             (transform (relational-op-function 1 (lambda (p) (relational-op-union p foreign)))))
        (reject-change transform)))
    (test-case "valid mutations are seen on the next call and outputs are detached"
      (let* ((source (relational-op-source 'captured 1 '((a))))
             (transform (relational-op-function 1 (lambda (p) (relational-op-union p source)))))
        (let-values (((base grown delta) (relational-op-delta-change transform [] [])))
          (set-car! (car base) 'changed)
          (check-equal? (vector-ref (relational-op-data source) 1) '((a))))
        (vector-set! (relational-op-data source) 1 '((b)))
        (let-values (((base grown delta) (relational-op-delta-change transform [] [])))
          (check-equal? base '((b)))
          (check-equal? grown '((b)))
          (check-equal? delta []))))
    (test-case "prepared plan owns captures metadata and each published row"
      (let* ((node #f)
             (transform (relational-op-function 1 (lambda (p)
                          (set! node (relational-op-flatmap p 1 '(((0) (a)) ((1) (b))))) node)))
             (plan (relational-op-prepare-change transform)))
        (vector-set! (relational-op-data node) 1 '((0 (mutable))))
        (set-car! (relational-op-inputs node) node)
        (reject-change transform)
        (let-values (((base grown delta) (relational-op-change plan '((0)) '((1)))))
          (check-equal? base '((a)))
          (check-equal? grown '((a) (b)))
          (check-equal? delta '((b)))
          (set-car! (car base) 'changed)
          (set-car! (car delta) 'changed)
          (check-equal? grown '((a) (b))))
        (check-exception (relational-op-change plan [] '((0) (1)) 1) (lambda (_) #t))
        (let-values (((base grown delta) (relational-op-change plan '((0)) '((1)))))
          (check-equal? grown '((a) (b))))))
    (test-case "captured source and mapping rows match independent owned-graph reanalysis"
      (let* ((source (relational-op-source 'captured 1 '((a) (a))))
             (inner (relational-op-function 1 (lambda (p)
                      (relational-op-flatmap p 1 '(((a) (b)) ((b) (c)))))))
             (transform (relational-op-function 1 (lambda (p)
                          (relational-op-union source
                            (relational-op-fix 1 (lambda (q)
                              (relational-op-union (relational-op-apply inner p) q)))))))
             (capture (capture-operator-transform transform))
             (owned (operator-snapshot-transform capture))
             (rows (operator-snapshot-checked-rows capture))
             (input (relational-op-source 'probe 1 []))
             (reference (operator-analysis-checked-rows
                          (analyze-operator-graph (relational-op-apply owned input)))))
        (check-equal? (hash-length rows) 2)
        (hash-for-each (lambda (node facts)
          (check-equal? facts (hash-ref reference node))) rows)
        (hash-for-each (lambda (node facts)
          (unless (eq? node input) (check-equal? facts (hash-ref rows node)))) reference)
        (vector-set! (relational-op-data source) 1 '((mutated)))
        (check-equal? (call-with-values
                       (cut relational-op-delta-change owned '((a)) '((b))) list)
                      (call-with-values
                       (cut relational-op-reference-change owned '((a)) '((b))) list))
        (hash-for-each (lambda (node facts)
          (check-equal? facts (hash-ref reference node))) rows)))
    (test-case "captured mapping indexes retain bucket order and isolate failed requests"
      (let* ((transform (relational-op-function 1 (lambda (p)
                          (relational-op-flatmap p 1
                            '(((0) (z)) ((1) (a)) ((0) (a)) ((0) (z)) ((2) (b)))))))
             (plan (relational-op-prepare-change transform)))
        (for-each (lambda (inputs)
          (let ((before (car inputs)) (added (cadr inputs)))
            (check-equal?
              (call-with-values (cut relational-op-change plan before added) list)
              (call-with-values (cut relational-op-delta-change transform before added) list))))
          '((() ()) (((0)) ()) (((0)) ((1))) (((2) (0)) ((1) (0))) (() ((0) (2)))))
        (check-exception (relational-op-change plan [] '((0)) 1) (lambda (_) #t))
        (let-values (((base grown delta) (relational-op-change plan [] '((0)))))
          ;; Existing normalization retains the last duplicate z, after a.
          (check-equal? base [])
          (check-equal? grown '((a) (z)))
          (check-equal? delta '((a) (z)))
          (set-car! (car grown) 'changed))
        (let-values (((base grown delta) (relational-op-change plan [] '((0)))))
          (check-equal? grown '((a) (z)))
          (check-equal? delta '((a) (z))))))
    (test-case "prepared nested feedback and applications retain lexical identities"
      (let* ((inner (relational-op-function 1 (lambda (p) (relational-op-project p '(0)))))
             (transform (relational-op-function 1 (lambda (input)
               (relational-op-fix 1 (lambda (outer)
                 (relational-op-union (relational-op-apply inner input)
                   (relational-op-fix 1 (lambda (inside) (relational-op-union outer inside)))))))))
             (plan (relational-op-prepare-change transform)))
        (check-equal?
         (call-with-values (cut relational-op-change plan '((a)) '((b))) list)
         (call-with-values (cut relational-op-reference-change transform '((a)) '((b))) list))))))
