;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import "objects.ss"
        (only-in "aggregators.ss"
                 gerbil-ascent-count gerbil-ascent-sum
                 gerbil-ascent-min gerbil-ascent-max)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export relational-scalar? relational-copy-rows relational-finite-rows
        relational-source
        relational-checked-lattice relational-lattice-fragment
        relational-finite-view relational-captured-value
        relational-term-fingerprint relational-reducer
        relational-operator-literal relational-operand-variables
        relational-where relational-compute)

;;; The checked language admits only scalar atoms with stable equality and
;;; hash behavior. Copy list spines before a source or mapping retains rows.
(def (relational-scalar? value)
  (or (exact-integer? value) (boolean? value)
      (symbol? value) (char? value)))

(def (relational-copy-row row arity)
  (unless (and (list? row) (= (length row) arity)
               (andmap relational-scalar? row))
    (error "relational row has wrong arity or non-scalar value" row))
  (map identity row))

(def (relational-copy-rows rows arity)
  (unless (and (exact-integer? arity) (<= 0 arity) (list? rows))
    (error "invalid relational row signature" arity))
  (map (lambda (row) (relational-copy-row row arity)) rows))

;;; Materialize a finite pointwise graph at construction. Missing inputs
;;; produce no rows, repeated inputs produce several, and evaluation uses
;;; ordinary relation joins without invoking a captured host procedure.
(def (relational-finite-rows input-arity output-arity entries)
  (unless (and (exact-integer? input-arity) (<= 0 input-arity)
               (exact-integer? output-arity) (<= 0 output-arity)
               (list? entries))
    (error "invalid finite view signature"))
  (map
   (lambda (entry)
     (unless (and (list? entry) (= (length entry) 2))
       (error "finite view entry needs input and output rows" entry))
     (append (relational-copy-row (car entry) input-arity)
             (relational-copy-row (cadr entry) output-arity)))
   entries))

;;; Restrict sources and results to immutable scalar atoms. Computed exact
;;; integers can grow beyond the source domain; budgets stop such a solve as
;;; failure and must never be read as evidence of completed closure.
(def (relational-source name arity rows)
  ;; Retain the scalar restriction on later source replacement and on
  ;; derived rows.  The relation constructor already checks every row.
  (gerbil-ascent-relation
   name arity (relational-copy-rows rows arity)
   gerbil-ascent-hash-index-provider
   gerbil-ascent-set-storage-provider
   (make-list arity relational-scalar?)))

;;; Lattice joins are chosen by a closed descriptor and rebuilt during
;;; admission. The last column is an exact integer; keys stay scalar.
(def (relational-lattice-join mode)
  (case mode
    ((max)
     (lambda (left right)
       (unless (and (exact-integer? left) (exact-integer? right))
         (error "max lattice needs exact integer values"))
       (max left right)))
    ((min)
     (lambda (left right)
       (unless (and (exact-integer? left) (exact-integer? right))
         (error "min lattice needs exact integer values"))
       (min left right)))
    (else (error "unknown checked lattice join" mode))))

(def (relational-checked-lattice name arity rows mode)
  (unless (and (exact-integer? arity) (> arity 0) (list? rows))
    (error "invalid checked lattice signature" name arity))
  (let (copied (relational-copy-rows rows arity))
    (for-each
     (lambda (row)
       (unless (exact-integer? (last row))
         (error "checked lattice needs exact integer value" row)))
     copied)
    (gerbil-ascent-lattice
     name arity copied
     (relational-lattice-join mode)
     gerbil-ascent-hash-index-provider
     (append (make-list (- arity 1) relational-scalar?)
             (list exact-integer?))
     (vector 'lattice mode))))

;;; A lattice fragment is one source declaration with a fresh handle.
;;; Its label can be imported by rule fragments without exposing the
;;; private relation name or trusting a caller-supplied join procedure.
(def (relational-lattice-fragment label arity rows mode)
  (unless (symbol? label)
    (error "lattice fragment label must be a symbol" label))
  (let (handle (gensym 'lattice))
    (gerbil-ascent-fragment
     (list (relational-checked-lattice handle arity rows mode))
     [] (list (cons label handle)) (list handle))))

;;; An explicit finite pointwise view is an extensional source fragment.
;;; A rule imports its handle and joins the input/output columns normally;
;;; unlisted inputs have no outputs and repeated inputs have many.
(def (relational-finite-view label input-arity output-arity entries)
  (unless (symbol? label)
    (error "finite view label must be a symbol" label))
  (let (handle (gensym 'view))
    (gerbil-ascent-fragment
     (list (relational-source
            handle (+ input-arity output-arity)
            (relational-finite-rows input-arity output-arity entries)))
     [] (list (cons label handle)) (list handle))))

;;; An explicit host capture is evaluated when the program or fragment is
;;; constructed. Restrict it to immutable scalar values before any rule can
;;; observe it; mutable collections cannot be smuggled into a solved graph.
(def (relational-captured-value value)
  (unless (relational-scalar? value)
    (error "relational value capture requires an immutable scalar" value))
  (gerbil-ascent-literal value))

;;; A rule-local literal is fixed when its program or fragment is built.
;;; The descriptor is copied again at admission, so later caller mutation
;;; cannot alter an executing rule. Symbols in the input list denote logic
;;; variables; vectors distinguish explicitly captured literal values.
(def (relational-operator-literal value)
  (unless (relational-scalar? value)
    (error "relational operator literal requires a scalar" value))
  (vector 'literal value))

(def (relational-copy-operand operand)
  (cond
   ((symbol? operand) (vector 'variable operand))
   ((and (vector? operand) (= (vector-length operand) 2))
    (case (vector-ref operand 0)
      ((variable)
       (unless (symbol? (vector-ref operand 1))
         (error "invalid relational operator variable" operand))
       (vector 'variable (vector-ref operand 1)))
      ((literal) (relational-operator-literal (vector-ref operand 1)))
      (else (error "invalid relational operator operand" operand))))
   (else (error "invalid relational operator operand" operand))))

(def (relational-operand-variables operands)
  (unless (list? operands)
    (error "relational operator operands must be a list" operands))
  (filter-map
   (lambda (operand)
     (and (vector? operand)
          (= (vector-length operand) 2)
          (eq? (vector-ref operand 0) 'variable)
          (vector-ref operand 1)))
   operands))

(def (relational-operator-call operation-procedure operands)
  (lambda values
    (let loop ((remaining operands) (bound values) (arguments []))
      (if (null? remaining)
        (begin
          (unless (null? bound)
            (error "relational operator argument mismatch"))
          (apply operation-procedure (reverse arguments)))
        (let (operand (car remaining))
          (if (eq? (vector-ref operand 0) 'variable)
            (if (pair? bound)
              (loop (cdr remaining) (cdr bound)
                    (cons (car bound) arguments))
              (error "relational operator argument mismatch"))
            (loop (cdr remaining) bound
                  (cons (vector-ref operand 1) arguments))))))))

(def (relational-term-fingerprint terms)
  (map (lambda (term)
         (cons (.ref term 'kind) (.ref term 'value)))
       terms))

;;; Fixed reducers consume a completed lower stratum. A procedure stored
;;; in a caller-owned Aggregate is never accepted on its own authority.
(def (relational-reducer-procedure mode inputs)
  (case mode
    ((count)
     (unless (null? inputs)
       (error "checked count takes no value variable"))
     gerbil-ascent-count)
    ((sum min max)
     (unless (= (length inputs) 1)
       (error "checked numeric reduction needs one value variable"))
     (let (reducer (case mode
                    ((sum) gerbil-ascent-sum)
                    ((min) gerbil-ascent-min)
                    ((max) gerbil-ascent-max)))
       (lambda (tuples)
         (for-each
          (lambda (tuple)
            (unless (and (list? tuple) (= (length tuple) 1)
                         (exact-integer? (car tuple)))
              (error "numeric reduction needs exact integer rows")))
          tuples)
         (reducer tuples))))
    (else (error "unknown checked reducer" mode))))

(def (relational-reducer output mode inputs relation terms)
  (gerbil-ascent-aggregate
   output relation terms inputs
   (relational-reducer-procedure mode inputs) #f
   (vector 'reduce mode output relation
           (map identity inputs)
           (relational-term-fingerprint terms))))

;;; Fixed scalar operators are declared by name, arity and input mode.
;;; Their procedures are built locally; a rule cannot supply a host closure.
(def (relational-operator-procedure mode operation arity)
  (case mode
    ((where)
     (case operation
       ((even?)
        (unless (= arity 1)
          (error "even? expects one relational input"))
        (lambda (value)
          (unless (exact-integer? value)
            (error "even? expects an exact integer" value))
          (even? value)))
       ((<)
        (unless (= arity 2)
          (error "< expects two relational inputs"))
        (lambda (left right)
          (unless (and (exact-integer? left) (exact-integer? right))
            (error "< expects exact integers" left right))
          (< left right)))
       (else (error "unknown relational filter operator" operation))))
    ((compute)
     (case operation
       ((+)
        (unless (= arity 2)
          (error "+ expects two relational inputs"))
        (lambda (left right)
          (unless (and (exact-integer? left) (exact-integer? right))
            (error "+ expects exact integers" left right))
          (+ left right)))
       ((identity)
        (unless (= arity 1)
          (error "identity expects one relational input"))
        (lambda (value) value))
       (else (error "unknown relational projection operator" operation))))
    (else (error "unknown relational operator mode" mode))))

(def (relational-where operation variables)
  (let* ((operands (map relational-copy-operand variables))
         (inputs (relational-operand-variables operands)))
    (gerbil-ascent-guard
     inputs
     (relational-operator-call
      (relational-operator-procedure 'where operation (length operands))
      operands)
     (vector 'where operation operands))))

(def (relational-compute output operation variables)
  (let* ((operands (map relational-copy-operand variables))
         (inputs (relational-operand-variables operands)))
    (gerbil-ascent-binding
     output inputs
     (relational-operator-call
      (relational-operator-procedure 'compute operation (length operands))
      operands)
     (vector 'compute operation operands output))))
