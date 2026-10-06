;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One admission owns graph validation, detached finite rows and lexical sets.
;;; Shared metadata is never cached across calls over mutable descriptors.
(import "operator-descriptor.ss"
        (only-in "scheme-checked.ss" relational-scalar? relational-copy-rows)
        (only-in :std/list/list append-map delete-duplicates/hash))
(export analyze-operator-graph operator-analysis-checked-rows operator-analysis-free-cache free-parameters)
(defstruct operator-analysis (checked-rows free-cache))

;;; Compute lexical dependencies before consulting the shared compiler memo.
;;; Otherwise a child cached while its fix parameter is bound could be
;;; silently reused outside that fix and capture its private relation.
;; : (-> RelationalOp (IdentityTable RelationalOp (List RelationalOp)) (List RelationalOp))
(def (free-parameters node cache)
  (let (cached (hash-get cache node))
    (if cached
      cached
      (let* ((inputs (relational-op-inputs node))
             (free
              (case (relational-op-kind node)
                ((parameter) (list node))
                ((fix)
                 (filter
                  (lambda (parameter)
                    (not (eq? parameter (relational-op-data node))))
                  (free-parameters (car inputs) cache)))
                ((apply)
                 (let (transform (relational-op-data node))
                   (append
                    (free-parameters (car inputs) cache)
                    (filter
                     (lambda (parameter)
                       (not (eq? parameter
                                 (relational-transform-parameter transform))))
                     (free-parameters
                      (relational-transform-body transform) cache)))))
                (else
                 (append-map (lambda (input)
                               (free-parameters input cache))
                             inputs)))))
        ;; A dependency is an identity, not one entry per path through a DAG.
        ;; Keep first traversal order so lexical memo keys remain deterministic.
        (set! free (if (or (null? free) (null? (cdr free))) free
                       (delete-duplicates/hash free table: (make-hash-table-eq) from-end?: #t)))
        (hash-put! cache node free)
        free))))

;;; Public descriptor accessors expose mutable list/vector spines. Recheck
;;; the complete graph before scope analysis or emission; feedback uses a
;;; parameter node, never a pointer cycle in the descriptor graph itself.
;; : (-> RelationalOp OperatorAnalysis)
(def (analyze-operator-graph root)
  (let ((states (make-hash-table-eq))
        (checked-rows (make-hash-table-eq)) (free-cache (make-hash-table-eq)))
    (def (reject) (error "invalid or mutated operator descriptor"))
    (def (visit node)
      (require-op node)
      (case (hash-get states node)
        ((visiting) (error "cyclic operator descriptor graph"))
        ((checked) (void))
        (else
         (hash-put! states node 'visiting)
         (let ((kind (relational-op-kind node))
               (arity (relational-op-arity node))
               (inputs (relational-op-inputs node))
               (data (relational-op-data node)))
           (unless (and (exact-integer? arity) (>= arity 0) (list? inputs)) (reject))
           (let (count (case kind ((source parameter) 0) ((union join) 2)
                            ((select-eq project flatmap fix apply) 1) (else #f)))
             (unless (and count (= (length inputs) count)) (reject)))
           (for-each visit inputs)
           (case kind
             ((source)
              (unless (and (vector? data) (= (vector-length data) 2)
                           (symbol? (vector-ref data 0))) (reject))
              (hash-put! checked-rows node (relational-copy-rows (vector-ref data 1) arity)))
             ((parameter) (unless (eq? data #f) (reject)))
             ((union)
              (unless (and (eq? data #f)
                           (andmap (lambda (input) (= arity (relational-op-arity input))) inputs)) (reject)))
             ((join)
              (unless (and (vector? data) (= (vector-length data) 2)
                           (= arity (+ (relational-op-arity (car inputs)) (relational-op-arity (cadr inputs))))
                           (valid-column? (vector-ref data 0) (relational-op-arity (car inputs)))
                           (valid-column? (vector-ref data 1) (relational-op-arity (cadr inputs)))) (reject)))
             ((select-eq)
              (unless (and (vector? data) (= (vector-length data) 2)
                           (= arity (relational-op-arity (car inputs)))
                           (valid-column? (vector-ref data 0) arity)
                           (relational-scalar? (vector-ref data 1))) (reject)))
             ((project)
              (unless (and (list? data) (= arity (length data))
                           (andmap (lambda (column) (valid-column? column (relational-op-arity (car inputs)))) data)) (reject)))
             ((flatmap)
              (unless (and (vector? data) (= (vector-length data) 2)
                           (equal? (vector-ref data 0) (relational-op-arity (car inputs)))) (reject))
              (hash-put! checked-rows node
                         (relational-copy-rows (vector-ref data 1) (+ arity (vector-ref data 0)))))
             ((fix)
              (visit data)
              (unless (and (eq? (relational-op-kind data) 'parameter)
                           (= arity (relational-op-arity data))
                           (= arity (relational-op-arity (car inputs)))) (reject)))
             ((apply)
              (unless (relational-transform? data) (reject))
              (let ((parameter (relational-transform-parameter data))
                    (body (relational-transform-body data)))
                (visit parameter) (visit body)
                (unless (and (eq? (relational-op-kind parameter) 'parameter)
                             (equal? (relational-transform-input-arity data) (relational-op-arity parameter))
                             (equal? (relational-transform-output-arity data) (relational-op-arity body))
                             (= (relational-op-arity parameter) (relational-op-arity (car inputs)))
                             (= arity (relational-op-arity body))) (reject))))))
         (hash-put! states node 'checked))))
    (visit root)
    (unless (null? (free-parameters root free-cache))
      (error "operator fixed-point parameter escaped its body"))
    (make-operator-analysis checked-rows free-cache)))
