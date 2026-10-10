;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Independent set interpretation of admitted finite descriptors. This public
;;; semantic path does not call the rule planner or semi-naive native evaluator.
(import "operator-descriptor.ss" "operator-analysis.ss" "operator-measurement.ss"
        (only-in :std/list/list append-map delete-duplicates/hash take))
(export relational-op-reference relational-op-reference-change)
;;; This deliberately simple set interpreter is the executable meaning of
;;; the finite operator graph. It shares descriptors with compilation but
;;; never calls the rule planner, index provider, or semi-naive evaluator.
;;; Exceeding a bound raises; it never returns a partial set as closure.
;; : (-> RelationalOp ?PositiveInteger (List (List Scalar)))
(def (relational-op-reference root (row-limit 4096))
  (def checked-rows (operator-analysis-checked-rows (analyze-operator-graph root)))
  (unless (and (exact-integer? row-limit) (> row-limit 0))
    (error "reference row limit must be positive" row-limit))
  (def (normalize rows)
    (let (unique (delete-duplicates/hash rows))
      (when (> (length unique) row-limit)
        (error "operator reference row limit exceeded" row-limit))
      unique))
  (def (same-set? left right)
    (and (= (length left) (length right))
         (andmap (lambda (row) (member row right)) left)))
  (def (evaluate node environment)
    (let ((kind (relational-op-kind node))
          (inputs (relational-op-inputs node))
          (data (relational-op-data node)))
      (case kind
        ((source) (normalize (hash-ref checked-rows node)))
        ((parameter)
         (let (binding (assq node environment))
           (unless binding
             (error "operator reference parameter escaped its fixed point"))
           (cdr binding)))
        ((union)
         (normalize (append (evaluate (car inputs) environment)
                            (evaluate (cadr inputs) environment))))
        ((join)
         (let ((left (evaluate (car inputs) environment))
               (right (evaluate (cadr inputs) environment))
               (left-key (vector-ref data 0))
               (right-key (vector-ref data 1)))
           (normalize
            (append-map
             (lambda (left-row)
               (map
                (lambda (right-row) (append left-row right-row))
                (filter
                 (lambda (right-row)
                   (relational-op-count-join!)
                   (equal? (list-ref left-row left-key)
                           (list-ref right-row right-key)))
                 right)))
             left))))
        ((select-eq)
         (normalize
          (filter (lambda (row)
                    (equal? (list-ref row (vector-ref data 0))
                            (vector-ref data 1)))
                  (evaluate (car inputs) environment))))
        ((project)
         (normalize
          (map (lambda (row)
                 (map (lambda (column) (list-ref row column)) data))
               (evaluate (car inputs) environment))))
        ((flatmap)
         (let ((width (vector-ref data 0))
               (table (hash-ref checked-rows node)))
           (normalize
            (append-map
             (lambda (row)
               (map (lambda (entry) (list-tail entry width))
                    (filter
                     (lambda (entry)
                       (equal? row (take entry width)))
                     table)))
             (evaluate (car inputs) environment)))))
        ((apply)
         (let ((transform data)
               (argument (evaluate (car inputs) environment)))
           (evaluate
            (relational-transform-body transform)
            (cons (cons (relational-transform-parameter transform)
                        argument)
                  environment))))
        ((fix)
         (let ((body (car inputs))
               (parameter data))
           (let loop ((current []))
             (let (next
                   (normalize
                    (append current
                            (begin
                              (relational-op-count-fix!)
                              (evaluate body
                                        (cons (cons parameter current)
                                              environment))))))
               (if (same-set? next current)
                 current
                 (loop next))))))
        (else (error "unsupported reference operator node" kind)))))
  (evaluate root []))

;;; Reference change is defined by two complete interpretations. It is not
;;; an optimized delta evaluator: the before and grown result sets are
;;; compared only after each fixed point has completed within its bound.
;; : (-> RelationalTransform ScalarRows ScalarRows ?PositiveInteger (values ScalarRows ScalarRows))
(def (relational-op-reference-change transformer before added
                                      (row-limit 4096))
  (unless (relational-transform? transformer)
    (error "expected a relation transformer" transformer))
  (let* ((arity (relational-transform-input-arity transformer))
         (base (relational-op-reference
                (relational-op-apply
                 transformer (relational-op-source
                              (gensym 'before) arity before))
                row-limit))
         (grown (relational-op-reference
                 (relational-op-apply
                  transformer (relational-op-source
                               (gensym 'grown) arity
                               (append before added)))
                 row-limit)))
    (for-each
     (lambda (row)
       (unless (member row grown)
         (error "relation transformer violated positive change" row)))
     base)
    (values base grown
            (filter (lambda (row) (not (member row base))) grown))))
