;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Finite operator lowering into rules, with the stable public facade.
;;; Descriptor construction, graph admission and set interpretation have
;;; separate owners; only this invocation emits private relation handles.
(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop define-type validate)
        (only-in :core/types PooFlowNativeObjectContract. poo-flow-predicate-contract)
        "operator-descriptor.ss" "operator-analysis.ss" "operator-measurement.ss" "operator-reference.ss"
        (only-in "objects.ss" gerbil-ascent-relation gerbil-ascent-program gerbil-ascent-rule
                 gerbil-ascent-atom gerbil-ascent-variable gerbil-ascent-fragment))

(export GerbilAscentOperatorCompilerContract relational-op-compiler
        relational-op-source relational-op-union relational-op-join
        relational-op-select-eq relational-op-project
        relational-op-flatmap relational-op-fix
        relational-op-function relational-op-apply
        relational-op-compile relational-op-fragment
        relational-op-reference relational-op-reference-change
        relational-op-kind relational-op-inputs relational-op-data
        relational-transform? relational-transform-parameter
        relational-transform-body relational-transform-input-arity
        relational-op-measure relational-op-measurement?
        relational-op-measurement-result-values
        relational-op-measurement-join-probes
        relational-op-measurement-fix-body-evaluations
        relational-op-count-join! relational-op-count-fix!
        relational-op? relational-op-arity)

(def (fresh-variables arity)
  (map (lambda (_column) (gensym '?column)) (iota arity)))

(def (variable-atom name variables)
  (gerbil-ascent-atom name (map gerbil-ascent-variable variables)))

(def (copy-rule target source arity)
  (let (variables (fresh-variables arity))
    (gerbil-ascent-rule
     (list (variable-atom target variables))
     (list (variable-atom source variables)))))

;;; A join's shared key uses the same variable on both atoms. Projection
;;; may select either copy, including repeated columns, without changing
;;; the set of output tuples.
(def (join-variables node)
  (let* ((inputs (relational-op-inputs node))
         (left-vars (fresh-variables (relational-op-arity (car inputs))))
         (left-key (vector-ref (relational-op-data node) 0))
         (right-key (vector-ref (relational-op-data node) 1))
         (right-vars
          (map (lambda (column)
                 (if (= column right-key)
                   (list-ref left-vars left-key)
                   (gensym '?right)))
               (iota (relational-op-arity (cadr inputs))))))
    (values left-vars right-vars)))

;;; Compilation is finite and instance-local. A placeholder may be read
;;; only inside its own fix body; distinct source nodes cannot silently
;;; alias the same public name, even when their rows happen to match.
(def (lower-operator-graph root fresh-sources? (make-relation gerbil-ascent-relation))
  (let* ((analysis (analyze-operator-graph root))
         (checked-rows (operator-analysis-checked-rows analysis))
        (relations []) (rules []) (sources [])
        (memo (make-hash-table-eq))
        (free-cache (operator-analysis-free-cache analysis))
        (names (make-hash-table-eq))
        (source-labels []))
    (def (add-derived arity)
      (let (name (gensym 'operator))
        (set! relations
          (cons (make-relation name arity []) relations))
        name))
    (def (add-rule rule)
      (set! rules (cons rule rules)))
    ;; Cache a node under the actual lexical relation handles it captures.
    ;; Descriptor identity owns the outer table; binding lists own instances.
    (def (remember node name bindings)
      (let (instances (or (hash-get memo node)
                          (let (table (make-hash-table))
                            (hash-put! memo node table) table)))
        (hash-put! instances bindings name))
      name)

    ;; Inputs are already lowered in graph order. This handler only emits
    ;; the rules and private source relations of an ordinary operation.
    (def (emit-operation-rules! node name input-names)
      (let ((kind (relational-op-kind node))
            (inputs (relational-op-inputs node)))
        (case kind
          ((union)
           (for-each
            (lambda (input)
              (add-rule
               (copy-rule name input (relational-op-arity node))))
            input-names))
          ((join)
           (let-values (((left-vars right-vars)
                         (join-variables node)))
             (add-rule
              (gerbil-ascent-rule
               (list (variable-atom
                      name (append left-vars right-vars)))
               (list (variable-atom (car input-names) left-vars)
                     (variable-atom (cadr input-names)
                                    right-vars))))))
          ((select-eq)
           (let* ((variables
                   (fresh-variables
                    (relational-op-arity (car inputs))))
                  (column (vector-ref (relational-op-data node) 0))
                  (value (vector-ref (relational-op-data node) 1))
                  (constant-name (gensym 'selection)))
             (set! relations
               (cons (make-relation
                      constant-name 1 (list (list value)))
                     relations))
             (set! sources (cons constant-name sources))
             (add-rule
              (gerbil-ascent-rule
               (list (variable-atom name variables))
               (list (variable-atom
                      (car input-names) variables)
                     (variable-atom
                      constant-name
                      (list (list-ref variables column))))))))
          ((project)
           (let* ((variables
                   (fresh-variables
                    (relational-op-arity (car inputs))))
                  (selected
                   (map (lambda (column)
                          (list-ref variables column))
                        (relational-op-data node))))
             (add-rule
              (gerbil-ascent-rule
               (list (variable-atom name selected))
               (list (variable-atom
                      (car input-names) variables))))))
          ((flatmap)
           (let* ((data (relational-op-data node))
                  (input-arity (vector-ref data 0))
                  (mapping-name (gensym 'mapping))
                  (in (fresh-variables input-arity))
                  (out (fresh-variables
                        (relational-op-arity node))))
             (set! relations
               (cons (make-relation
                      mapping-name
                      (+ input-arity (relational-op-arity node))
                      (hash-ref checked-rows node))
                     relations))
             (set! sources (cons mapping-name sources))
             (add-rule
              (gerbil-ascent-rule
               (list (variable-atom name out))
               (list (variable-atom (car input-names) in)
                     (variable-atom mapping-name
                                    (append in out)))))))
          (else (error "unsupported operator node" kind)))))

    ;; Resolve every free parameter before memo lookup. An escaped child is
    ;; rejected even if an instance of it was compiled under another binding.
    (def (emit node active)
      (let (free (free-parameters node free-cache))
        (for-each
         (lambda (parameter)
           (unless (assq parameter active)
             (error "operator fixed-point parameter escaped its body")))
         free)
        (let* ((bindings (map (lambda (parameter) (cdr (assq parameter active))) free))
               (kind (relational-op-kind node))
               (instances (hash-get memo node))
               (cached (and instances (hash-get instances bindings))))
          (cond
           ((eq? kind 'parameter)
            (let (binding (assq node active))
              (unless binding
                (error "operator fixed-point parameter escaped its body"))
              (cdr binding)))
           (cached cached)
           ((eq? kind 'source)
            (let* ((data (relational-op-data node))
                   (label (vector-ref data 0))
                   (name (if fresh-sources? (gensym label) label)))
              (when (hash-get names label)
                (error "duplicate operator source name" label))
              (hash-put! names label #t)
              (set! source-labels
                (cons (cons label name) source-labels))
              (set! sources (cons name sources))
              (set! relations
                (cons (make-relation
                       name (relational-op-arity node)
                       (hash-ref checked-rows node))
                      relations))
              (remember node name bindings)))
           ((eq? kind 'fix)
            (let* ((name (add-derived (relational-op-arity node)))
                   (body (car (relational-op-inputs node)))
                   (parameter (relational-op-data node)))
              (remember node name bindings)
              ;; A fixed point of a union is the least relation receiving
              ;; each branch directly. Materializing the union and copying
              ;; it back into the fixed-point relation adds no tuples.
              (let (body-active (cons (cons parameter name) active))
                (if (eq? (relational-op-kind body) 'union)
                  (for-each
                   (lambda (branch)
                     (add-rule
                      (copy-rule name (emit branch body-active)
                                 (relational-op-arity node))))
                   (relational-op-inputs body))
                  (add-rule
                   (copy-rule name (emit body body-active)
                              (relational-op-arity node)))))
              name))
           ((eq? kind 'apply)
            (let* ((transform (relational-op-data node))
                   (input-name
                    (emit (car (relational-op-inputs node)) active))
                   (result
                    (emit (relational-transform-body transform)
                          (cons
                           (cons (relational-transform-parameter transform)
                                 input-name)
                           active))))
              (remember node result bindings)))
           ((and (eq? kind 'project)
                 (eq? (relational-op-kind
                       (car (relational-op-inputs node))) 'join))
            (let* ((joined (car (relational-op-inputs node)))
                   (names (map (lambda (input) (emit input active))
                               (relational-op-inputs joined)))
                   (name (add-derived (relational-op-arity node))))
              (let-values (((left-vars right-vars)
                            (join-variables joined)))
                (let* ((variables (append left-vars right-vars))
                       (selected
                        (map (lambda (column)
                               (list-ref variables column))
                             (relational-op-data node))))
                  (add-rule
                   (gerbil-ascent-rule
                    (list (variable-atom name selected))
                    (list (variable-atom (car names) left-vars)
                          (variable-atom (cadr names) right-vars))))))
              (remember node name bindings)))
           (else
            (let* ((inputs (relational-op-inputs node))
                   (input-names (map (lambda (input) (emit input active))
                                     inputs))
                   (name (add-derived (relational-op-arity node))))
              (remember node name bindings)
              (emit-operation-rules! node name input-names)
              name))))))
    (let (output (emit root []))
      (values
       (reverse relations) (reverse rules) (reverse sources)
       output (reverse source-labels)))))

(def +compiler-procedure+
  (poo-flow-predicate-contract 'ascent/operator-compiler-procedure procedure?
                               (lambda (_value _context) [])))

;;; Only behavior lives in the prototype. Each call owns graph admission,
;;; private handles, memo tables and emitted relation/rule declarations.
(define-type (GerbilAscentOperatorCompilerContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/operator-compiler
  proto: (.o)
  responsibilities: (.o .make-relation: +compiler-procedure+
                      .compile: +compiler-procedure+))

(def OperatorCompiler. (.ref GerbilAscentOperatorCompilerContract 'proto))

(def (check-compiler-budgets! input-limit derived-limit output-limit)
  (unless (and (exact-integer? input-limit) (> input-limit 0)
               (exact-integer? derived-limit) (> derived-limit 0)
               (exact-integer? output-limit) (> output-limit 0))
    (error "operator program budgets must be positive exact integers")))

;;; The inherited method selects its final receiver's constructor once.
;;; Descriptor traversal never performs prototype dispatch in its row loop.
(def relational-op-compiler
  (validate GerbilAscentOperatorCompilerContract
    (.o (:: self OperatorCompiler.)
        (.make-relation gerbil-ascent-relation)
        (.compile
         (let (make-relation (.ref self '.make-relation))
           (lambda (root input-limit derived-limit output-limit)
             (check-compiler-budgets! input-limit derived-limit output-limit)
             (let-values (((relations rules sources output _labels)
                           (lower-operator-graph root #f make-relation)))
               (values
                (gerbil-ascent-program relations rules
                                       input-limit derived-limit output-limit sources)
                output))))))))

;; relational-op-compile
;;   : (-> RelationalOp Nat Nat Nat [OperatorCompiler | RelationConstructor] (Values Program Symbol))
;;   | doc m%
;;       Lower a descriptor graph to the same admitted positive-rule
;;       program consumed by the Scheme relational lifecycle.
;;       An optional PO compiler or compiler-owned constructor emits the final relation
;;       representation directly; it is used only during compilation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-op-compile
;;         (relational-op-source 'edge 2 '((1 2))) 8 8 16)
;;       ;; => program and a queryable relation handle
;;       ```
;;     %
;;; The standalone compiler keeps explicit source names for named queries.
;;; The optional owner is a derived compiler or the original constructor API.
(def (relational-op-compile root input-limit derived-limit output-limit
                           (compiler relational-op-compiler))
  (check-compiler-budgets! input-limit derived-limit output-limit)
  (let* ((selected
           (if (procedure? compiler)
             (.o (:: @ relational-op-compiler) (.make-relation compiler))
             compiler))
         (checked (validate GerbilAscentOperatorCompilerContract selected))
         (compile (.ref checked '.compile)))
    (compile root input-limit derived-limit output-limit)))

;;; A builder graph can participate in the same fragment lifecycle as native
;;; rules. Every named source gets a fresh handle per call; output and source
;;; labels are the only public entry points. Composition supplies budgets.
(def (relational-op-fragment root output-label)
  (unless (symbol? output-label)
    (error "operator fragment output label must be a symbol" output-label))
  (let-values (((relations rules sources output source-labels)
                (lower-operator-graph root #t)))
    (gerbil-ascent-fragment
     relations rules (cons (cons output-label output) source-labels)
     sources)))
