;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Included by the real semantic and performance modules. Fixture creation
;;; and all user callbacks are outside declaration timing.
(import (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-expression gerbil-ascent-pattern
                 gerbil-ascent-atom gerbil-ascent-generator
                 gerbil-ascent-aggregate gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program))
(export ascent-scope-fixture)

(def (scope-names prefix width)
  (map (lambda (n) (string->symbol (string-append prefix (number->string n))))
       (iota width)))

;;; Return a validated program and the ordered row every output must contain.
(def (ascent-scope-fixture kind width head-count)
  (let* ((names (scope-names "x" width))
         (outputs (scope-names "y" width))
         (variables (map gerbil-ascent-variable names))
         (row-values (cons #f (cdr (iota width))))
         (heads (scope-names "out" head-count))
         (body
          (case kind
            ((pattern)
             (list (gerbil-ascent-atom 'source
                      (list (gerbil-ascent-pattern names identity)))))
            ((generator)
             (list (gerbil-ascent-atom 'source variables)
                   (gerbil-ascent-generator outputs names
                     (lambda inputs (list inputs)))))
            ((aggregate)
             (list (gerbil-ascent-atom 'source (list (gerbil-ascent-variable 'seed)))
                   (gerbil-ascent-aggregate outputs 'input variables names
                     (lambda (tuples) (list (car tuples))) identity)))
            (else (list (gerbil-ascent-atom 'source variables)))))
         (head-terms
          (case kind
            ((expression)
             (list (gerbil-ascent-expression names (lambda inputs (length inputs)))))
            ((generator aggregate) (map gerbil-ascent-variable outputs))
            (else variables)))
         (expected (if (eq? kind 'expression) (list width) row-values))
         (relations
          (append
           (case kind
             ((pattern) (list (gerbil-ascent-relation 'source 1 (list (list row-values)))))
             ((aggregate)
              (list (gerbil-ascent-relation 'source 1 '((1)))
                    (gerbil-ascent-relation 'input width (list row-values))))
             (else (list (gerbil-ascent-relation 'source width (list row-values)))))
           (map (lambda (name)
                  (gerbil-ascent-relation name (length head-terms) [])) heads)))
         (rules
          (list (gerbil-ascent-rule
                 (map (lambda (name) (gerbil-ascent-atom name head-terms)) heads)
                 body))))
    (values (gerbil-ascent-program relations rules 64 64 128) expected heads)))
