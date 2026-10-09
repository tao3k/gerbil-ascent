;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Invocation-owned graph admission and rule emission. The compiler receiver
;;; selects constructors once; traversal contains no prototype dispatch.
(import :gerbil-ascent/program/operator-descriptor :gerbil-ascent/program/operator-analysis
 (only-in :gerbil-ascent/program/objects gerbil-ascent-atom gerbil-ascent-variable))
(export lower-operator-graph)

;;; A lexical variable owns one immutable POO term, reused by every atom
;;; header in its rule. Each scope still receives fresh uninterned names.
(def (fresh-variables arity)
  (map (lambda (_column) (gerbil-ascent-variable (gensym '?column))) (iota arity)))

(def (variable-atom name variables)
  (gerbil-ascent-atom name variables))

(def (copy-rule make-rule target source arity)
  (let (variables (fresh-variables arity))
    (make-rule
     (list (variable-atom target variables))
     (list (variable-atom source variables)))))

;;; Columns were admitted with the graph. Preserve variable identity and column
;;; order; multi-column reads share indexed tuples instead of rescanning lists.
(def (project-variables left columns (right []))
  (match columns
    ([] [])
    ([column]
     (list (if (null? right) (list-ref left column)
             (let (width (length left))
               (if (< column width) (list-ref left column)
                 (list-ref right (- column width)))))))
    (else
     (let* ((left-tuple (list->vector left)) (width (vector-length left-tuple))
            (right-tuple (list->vector right)))
       (map (lambda (column)
              (if (< column width) (vector-ref left-tuple column)
                (vector-ref right-tuple (- column width)))) columns)))))

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
                   (gerbil-ascent-variable (gensym '?right))))
               (iota (relational-op-arity (cadr inputs))))))
    (values left-vars right-vars)))

;;; Compilation is finite and instance-local. A placeholder may be read
;;; only inside its own fix body; distinct source nodes cannot silently
;;; alias the same public name, even when their rows happen to match.
(def (lower-operator-graph root fresh-sources? make-relation make-rule)
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
               (copy-rule make-rule name input (relational-op-arity node))))
            input-names))
          ((join)
           (let-values (((left-vars right-vars)
                         (join-variables node)))
             (add-rule
              (make-rule
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
              (make-rule
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
                  (selected (project-variables variables (relational-op-data node))))
             (add-rule
              (make-rule
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
              (make-rule
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
                      (copy-rule make-rule name (emit branch body-active)
                                 (relational-op-arity node))))
                   (relational-op-inputs body))
                  (add-rule
                   (copy-rule make-rule name (emit body body-active)
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
                (let ((selected (project-variables left-vars (relational-op-data node) right-vars)))
                  (add-rule
                   (make-rule
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
