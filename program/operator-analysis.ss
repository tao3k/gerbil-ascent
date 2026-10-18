;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One admission owns graph validation, detached finite rows and lexical sets.
;;; Shared metadata is never cached across calls over mutable descriptors.
(import "operator-descriptor.ss"
        (only-in "scheme-checked.ss" relational-scalar? relational-copy-rows)
        (only-in :std/list/list take)
        (only-in :std/list/list-builder with-list-builder))
(export analyze-operator-graph operator-analysis-checked-rows operator-analysis-free-cache free-parameters
        snapshot-operator-transform)
(defstruct operator-analysis (checked-rows free-cache))

;; Cached dependency lists are ordered identity sets. Reuse a complete spine
;; until a genuinely new dependency requires an owned result header.
(def (merge-free-parameters left right)
  (cond ((or (null? right) (eq? left right)) left)
        ((null? left) right)
        (else
         (let ((seen (make-hash-table-eq)) (extra []))
           (for-each (cut hash-put! seen <> #t) left)
           (for-each (lambda (parameter)
             (unless (hash-get seen parameter)
               (hash-put! seen parameter #t)
               (set! extra (cons parameter extra)))) right)
           (if (null? extra) left
             (with-list-builder (put!)
               (for-each put! left)
               (for-each put! (reverse! extra))))))))
(def (unbind-free-parameter free parameter)
  (if (memq parameter free) (filter (lambda (p) (not (eq? p parameter))) free) free))

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
                 (unbind-free-parameter (free-parameters (car inputs) cache)
                                        (relational-op-data node)))
                ((apply)
                 (let (transform (relational-op-data node))
                   (merge-free-parameters
                    (free-parameters (car inputs) cache)
                    (unbind-free-parameter
                     (free-parameters (relational-transform-body transform) cache)
                     (relational-transform-parameter transform)))))
                (else
                 (foldl (lambda (input free)
                          (merge-free-parameters free (free-parameters input cache)))
                        [] inputs)))))
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

;;; Clone the admitted graph through its constructors. The caller receives no
;;; internal node access: an execution plan keeps this graph behind its method.
;;; Identity memoization preserves shared children and each lexical binder.
(def (snapshot-operator-transform transform)
  (unless (relational-transform? transform) (error "expected a relation transformer"))
  (let* ((root (relational-op-apply transform
                 (relational-op-source (gensym 'snapshot-input)
                   (relational-transform-input-arity transform) [])))
         (rows (operator-analysis-checked-rows (analyze-operator-graph root)))
         (memo (make-hash-table-eq))
         (functions (make-hash-table-eq)))
    (def (copy-transform original)
      (or (hash-get functions original)
          (let (copied
                (relational-op-function
                 (relational-transform-input-arity original)
                 (lambda (parameter)
                   (hash-put! memo (relational-transform-parameter original) parameter)
                   (copy-node (relational-transform-body original)))))
            (hash-put! functions original copied)
            copied)))
    (def (copy-node node)
      (or (hash-get memo node)
          (let* ((inputs (relational-op-inputs node))
                 (data (relational-op-data node))
                 (copied
                  (case (relational-op-kind node)
                    ((source) (relational-op-source (vector-ref data 0)
                               (relational-op-arity node) (hash-ref rows node)))
                    ((union) (relational-op-union (copy-node (car inputs)) (copy-node (cadr inputs))))
                    ((join) (relational-op-join (copy-node (car inputs)) (copy-node (cadr inputs))
                             (vector-ref data 0) (vector-ref data 1)))
                    ((select-eq) (relational-op-select-eq (copy-node (car inputs))
                                  (vector-ref data 0) (vector-ref data 1)))
                    ((project) (relational-op-project (copy-node (car inputs)) data))
                    ((flatmap)
                     (let (width (vector-ref data 0))
                       (relational-op-flatmap (copy-node (car inputs)) (relational-op-arity node)
                         (map (lambda (row) (list (take row width) (list-tail row width)))
                              (hash-ref rows node)))))
                    ((fix) (relational-op-fix (relational-op-arity node)
                             (lambda (parameter)
                               (hash-put! memo data parameter)
                               (copy-node (car inputs)))))
                    ((apply) (relational-op-apply (copy-transform data) (copy-node (car inputs))))
                    (else (error "unbound parameter during operator snapshot")))))
            (hash-put! memo node copied)
            copied)))
    (copy-transform transform)))
