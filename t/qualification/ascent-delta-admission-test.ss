;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/program/operator
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
