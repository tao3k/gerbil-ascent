;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Insertion changes for the finite positive relation operator graph.
(import (only-in "operator.ss"
                 relational-op-kind relational-op-inputs
                 relational-op-data relational-transform?
                 relational-transform-parameter
                 relational-transform-body
                 relational-transform-input-arity
                 relational-op-count-join! relational-op-count-fix!)
        (only-in "scheme-checked.ss" relational-copy-rows)
        (only-in "operator-analysis.ss" analyze-operator-graph
                 operator-analysis-checked-rows snapshot-operator-transform)
        (only-in "operator-descriptor.ss" relational-op-apply
                 relational-op-source relational-transform-output-arity)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :core/types PooFlowNativeObjectContract. poo-flow-predicate-contract)
        (only-in :std/list/list append-map delete-duplicates/hash take)
        (only-in :std/list/list-builder with-list-builder))

(export relational-op-delta-change relational-op-prepare-change relational-op-change
        GerbilAscentChangePlanContract)

(define-type (GerbilAscentChangePlanContract @ PooFlowNativeObjectContract.)
  identity: 'ascent/operator-change-plan
  proto: (.o)
  responsibilities: (.o .change:
    (poo-flow-predicate-contract 'ascent/change-method procedure? (lambda (_value _context) []))))

;;; Closing the root with an empty input checks captures without borrowing or
;;; duplicating the request rows; only captured finite rows enter this table.
(def (change-analysis transformer)
  (operator-analysis-checked-rows
   (analyze-operator-graph
    (relational-op-apply transformer
     (relational-op-source (gensym 'delta-input)
                          (relational-transform-input-arity transformer) [])))))

;;; Admission owns all descriptor metadata and row spines once. Captured
;;; sources are fixed for this plan; callers create another plan to change them.
;;; Per-call inputs, budgets, environments and lookup registries remain local.
;; : (-> RelationalTransform ChangePlan)
(def (relational-op-prepare-change transformer)
  (let* ((owned (snapshot-operator-transform transformer))
         (rows (change-analysis owned)))
    (validate GerbilAscentChangePlanContract
      (.o (:: @ (.ref GerbilAscentChangePlanContract 'proto))
          (.change (lambda (before added (row-limit 4096))
                     (delta-change/admitted owned rows before added row-limit)))))))

;;; Constructor validation owns the method contract. Generic dispatch avoids
;;; rerunning graph/contract admission for every request on a prepared owner.
;; : (-> ChangePlan Rows Rows Nat (Values Rows Rows Rows))
(.defgeneric (execute-change-plan plan before added row-limit) slot: .change)
;; : (-> ChangePlan Rows Rows Nat (Values Rows Rows Rows))
(def (relational-op-change plan before added (row-limit 4096))
  (execute-change-plan plan before added row-limit))

;; relational-op-delta-change
;;   : (-> RelationalTransform Rows Rows Nat (Values Rows Rows Rows))
;;   | doc m%
;;       Propagate a positive input insertion through the finite operator
;;       graph. Joins use both cross terms and the new/new term. A fixed
;;       point starts at its completed old value, then propagates only its
;;       newly discovered rows until no frontier remains. Every intermediate
;;       relation is bounded; failure never returns a partial closure.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-op-delta-change transformer '((1 2)) '((2 3)))
;;       ;; => values: old rows, grown rows, newly derived rows
;;       ```
;;     %
(def (relational-op-delta-change transformer before added
                                 (row-limit 4096))
  (unless (relational-transform? transformer)
    (error "expected a relation transformer" transformer))
  (delta-change/admitted transformer (change-analysis transformer) before added row-limit))

;;; This private entry consumes either this call's admission or a plan's owned
;;; admission. Every mutable environment/index is still invocation-owned.
(def (delta-change/admitted transformer checked-rows before added row-limit)
  (unless (and (exact-integer? row-limit) (> row-limit 0))
    (error "delta row limit must be positive" row-limit))
  (let* ((arity (relational-transform-input-arity transformer))
         (old-input (relational-copy-rows before arity))
         (new-input (relational-copy-rows added arity)))
    (def (normalize rows)
      (let (unique (delete-duplicates/hash rows))
        (when (> (length unique) row-limit)
          (error "operator delta row limit exceeded" row-limit))
        unique))
    (def (difference rows old)
      ;; Every caller supplies normalized, bounded sets. Filtering preserves
      ;; both uniqueness and order; a second normalization has no work to do.
      (cond
        ((null? rows) [])
        ((null? old) rows)
        ((null? (cdr old))
         (filter (lambda (row) (not (equal? row (car old)))) rows))
        (else
         (let (seen (make-hash-table))
           (for-each (cut hash-put! seen <> #t) old)
           (filter (lambda (row) (not (hash-key? seen row))) rows)))))
    (def (union left right)
      (cond
        ((null? left) right)
        ((null? right) left)
        (else (normalize (append left right)))))
    (def (join left right left-key right-key)
      (normalize
       (append-map
        (lambda (left-row)
          (map (lambda (right-row) (append left-row right-row))
               (filter
                (lambda (right-row)
                  (relational-op-count-join!)
                  (equal? (list-ref left-row left-key)
                          (list-ref right-row right-key)))
                right)))
        left)))
    (def (select rows column value)
      (normalize
       (filter (lambda (row) (equal? (list-ref row column) value)) rows)))
    (def (project rows columns)
      (normalize
       (map (lambda (row)
              (map (lambda (column) (list-ref row column)) columns))
            rows)))
    ;; Finite mapping descriptors own frozen rows. Publish an ordered lookup
    ;; once per descriptor in this invocation, shared by base and frontiers.
    ;; Index only on demand: an empty change never visits the mapping table.
    (def mapping-indexes #f)
    (def (mapping-index node)
      (or (and mapping-indexes (hash-get mapping-indexes node))
          (let* ((data (relational-op-data node))
                 (width (vector-ref data 0))
                 (index (make-hash-table))
                 (keys
                  (with-list-builder (put!)
                    (for-each
                     (lambda (entry)
                       (let* ((key (take entry width))
                              (bucket (hash-get index key)))
                         (unless bucket (put! key))
                         (hash-put! index key
                                    (cons (list-tail entry width)
                                          (or bucket [])))))
                     (hash-ref checked-rows node)))))
            ;; These bucket spines belong to the index; table row tails do not.
            ;; Retain descriptor order so append-map observes the same rows.
            (for-each (lambda (key)
                        (hash-put! index key (reverse! (hash-ref index key))))
                      keys)
            (unless mapping-indexes
              (set! mapping-indexes (make-hash-table-eq)))
            (hash-put! mapping-indexes node index)
            index)))
    (def (scan-mapping node row)
      (let* ((data (relational-op-data node))
             (width (vector-ref data 0)))
        (with-list-builder (put!)
          (for-each
           (lambda (entry)
             (when (equal? row (take entry width))
               (put! (list-tail entry width))))
           (hash-ref checked-rows node)))))
    (def (flatmap node rows)
      (if (null? rows) []
        (let* ((published (and mapping-indexes
                               (hash-get mapping-indexes node)))
               ;; One query needs one scan. Multiple queries amortize an index;
               ;; a later singleton frontier reuses an already published one.
               (index (or published
                          (and (pair? (cdr rows)) (mapping-index node))))
               (lookup (if index
                         (lambda (row) (or (hash-get index row) []))
                         (cut scan-mapping node <>))))
          (normalize (append-map lookup rows)))))
    ;;; Bindings contain (before . added) sets. Replacing every binding by
    ;;; its grown set and an empty delta makes external changes stable while
    ;;; a recursive frontier advances through its fixed-point body.
    (def (grown-environment environment)
      (map (lambda (binding)
             (cons (car binding)
                   (cons (union (cadr binding) (cddr binding)) [])))
           environment))
    ;;; The frontier path asks only for a change. Zero-change children do
    ;;; not force an old join result; old operands are read only for cross
    ;;; terms that have a nonempty changing side. Nested fixed points use
    ;;; the complete change path until they have their own derivative.
    (def (derivative node environment)
      (let ((kind (relational-op-kind node))
            (inputs (relational-op-inputs node))
            (data (relational-op-data node)))
        (case kind
          ((source) [])
          ((parameter)
           (let (binding (assq node environment))
             (unless binding
               (error "operator delta parameter escaped its body"))
             (cddr binding)))
          ((union)
           (union (derivative (car inputs) environment)
                  (derivative (cadr inputs) environment)))
          ((join)
           (let* ((left (car inputs))
                  (right (cadr inputs))
                  (left-delta (derivative left environment))
                  (right-delta (derivative right environment))
                  (left-key (vector-ref data 0))
                  (right-key (vector-ref data 1)))
             (if (and (null? left-delta) (null? right-delta))
               []
               (let* ((left-old
                       (if (null? right-delta) []
                         (let-values (((base _delta)
                                       (change left environment))) base)))
                      (right-old
                       (if (null? left-delta) []
                         (let-values (((base _delta)
                                       (change right environment))) base))))
                 (union
                  (join left-delta right-old left-key right-key)
                  (union
                   (join left-old right-delta left-key right-key)
                   (join left-delta right-delta
                         left-key right-key)))))))
          ((select-eq)
           (select (derivative (car inputs) environment)
                   (vector-ref data 0) (vector-ref data 1)))
          ((project)
           (project (derivative (car inputs) environment) data))
          ((flatmap)
           (flatmap node (derivative (car inputs) environment)))
          ((apply)
           (let-values (((base delta)
                         (change (car inputs) environment)))
             (derivative
              (relational-transform-body data)
              (cons (cons (relational-transform-parameter data)
                          (cons base delta))
                    environment))))
          ((fix)
           (let-values (((_base delta) (change node environment)))
             delta))
          (else (error "unsupported delta operator node" kind)))))
    (def (change node environment)
      (let ((kind (relational-op-kind node))
            (inputs (relational-op-inputs node))
            (data (relational-op-data node)))
        (case kind
          ((source) (values (normalize (hash-ref checked-rows node)) []))
          ((parameter)
           (let (binding (assq node environment))
             (unless binding
               (error "operator delta parameter escaped its body"))
             (values (cadr binding) (cddr binding))))
          ((union)
           (let-values (((left left-delta)
                         (change (car inputs) environment))
                        ((right right-delta)
                         (change (cadr inputs) environment)))
             (let (base (union left right))
               (values base
                       (difference (union left-delta right-delta)
                                   base)))))
          ((join)
           (let-values (((left left-delta)
                         (change (car inputs) environment))
                        ((right right-delta)
                         (change (cadr inputs) environment)))
             (let* ((left-key (vector-ref data 0))
                    (right-key (vector-ref data 1))
                    (base (join left right left-key right-key))
                    (candidate
                     (union
                      (join left-delta right left-key right-key)
                      (union
                       (join left right-delta left-key right-key)
                       (join left-delta right-delta
                             left-key right-key)))))
               (values base (difference candidate base)))))
          ((select-eq)
           (let-values (((base delta)
                         (change (car inputs) environment)))
             (values (select base (vector-ref data 0)
                             (vector-ref data 1))
                     (select delta (vector-ref data 0)
                             (vector-ref data 1)))))
          ((project)
           (let-values (((base delta)
                         (change (car inputs) environment)))
             (let (result (project base data))
               (values result
                       (difference (project delta data) result)))))
          ((flatmap)
           (let-values (((base delta)
                         (change (car inputs) environment)))
             (let (result (flatmap node base))
               (values result
                       (difference
                        (flatmap node delta)
                        result)))))
          ((apply)
           (let-values (((base delta)
                         (change (car inputs) environment)))
             (change
              (relational-transform-body data)
              (cons (cons (relational-transform-parameter data)
                          (cons base delta))
                    environment))))
          ((fix)
           (let* ((body (car inputs))
                  (parameter data)
                  ;; External bindings do not change as this frontier moves.
                  ;; Delay publication so an empty frontier pays no map/union.
                  (steady (delay (grown-environment environment))))
             ;;; These recursions are the least-fixed-point closure and its
             ;;; delta frontier, rather than list-accumulator transforms.
             (letrec
               ((close
                 (lambda (current)
                   (relational-op-count-fix!)
                   (let-values (((body-base _body-delta)
                                 (change
                                  body
                                  (cons (cons parameter (cons current []))
                                        environment))))
                     (let (next (union current body-base))
                       (if (= (length next) (length current))
                         current
                         (close next))))))
                (advance
                 (lambda (base current frontier)
                   (if (null? frontier)
                     (values base (difference current base))
                     (let (grown (union current frontier))
                       (relational-op-count-fix!)
                       (let (next-delta
                             (derivative
                              body
                              (cons (cons parameter
                                          (cons current frontier))
                                    (force steady))))
                         (advance base grown
                                  (difference next-delta grown))))))))
               (let (base (close []))
                 (relational-op-count-fix!)
                 (let (initial-delta
                       (derivative
                        body
                        (cons (cons parameter (cons base []))
                              environment)))
                   (advance base base
                            (difference initial-delta base)))))))
          (else (error "unsupported delta operator node" kind)))))
    (let* ((base-input (normalize old-input))
           (delta-input (difference (normalize new-input) base-input)))
      (let-values (((base delta)
                    (change
                     (relational-transform-body transformer)
                     (list
                      (cons (relational-transform-parameter transformer)
                            (cons base-input delta-input))))))
        ;; Each publication owns row spines independently, including captured
        ;; source and mapping tails retained by a reusable plan.
        (let ((output-arity (relational-transform-output-arity transformer)))
          (values (relational-copy-rows base output-arity)
                  (relational-copy-rows (union base delta) output-arity)
                  (relational-copy-rows delta output-arity)))))))
