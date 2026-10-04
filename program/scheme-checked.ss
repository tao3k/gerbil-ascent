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

(export relational-scalar? relational-copy-row relational-copy-rows
        relational-finite-rows
        relational-source relational-finite-source relational-finite-lattice
        relational-checked-lattice relational-lattice-fragment
        relational-finite-view relational-captured-value
        relational-term-fingerprint relational-reducer
        relational-operator-literal relational-operand-variables
        relational-where relational-compute relational-stable-procedure?)

(def +stable-procedures+
  (make-hash-table test: eq? weak-keys: #t lock: (make-mutex)))

;;; Only procedures produced by these closed constructors may justify reuse.
;;; A caller-supplied descriptor on an opaque callback is not a semantic seal.
(def (relational-stable procedure)
  (hash-put! +stable-procedures+ procedure #t) procedure)
(def (relational-stable-procedure? procedure)
  (and (procedure? procedure) (hash-get +stable-procedures+ procedure) #t))

;;; The checked language admits only scalar atoms with stable equality and
;;; hash behavior. Copy list spines before a source or mapping retains rows.
(def (relational-scalar? value)
  (or (exact-integer? value) (boolean? value)
      (symbol? value) (char? value)))

;;; Shape admission precedes scalar checks, including improper/cyclic lists.
;; : (-> Row Arity Row)
(def (relational-check-row-shape! row arity)
  (unless (and (list? row) (= (length row) arity))
    (error "relational row has wrong arity or non-scalar value" row))
  row)

;;; Validation does not transfer ownership. append's input needs validation
;;; alone; its output is checked while copying into an independently owned tail.
;; : (-> Row Arity Row)
(def (relational-check-row! row arity)
  (relational-check-row-shape! row arity)
  (unless (andmap relational-scalar? row)
    (error "relational row has wrong arity or non-scalar value" row))
  row)

(def (relational-copy-row row arity)
  (relational-check-row-shape! row arity)
  (map (lambda (value)
         (unless (relational-scalar? value)
           (error "relational row has wrong arity or non-scalar value" row))
         value)
       row))

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
     ;; append copies the input spine itself. The output is copied once and
     ;; becomes the private tail; neither half retains caller-owned pairs.
     (let (input (relational-check-row! (car entry) input-arity))
       (append input (relational-copy-row (cadr entry) output-arity))))
   entries))

;;; Restrict sources and results to immutable scalar atoms. Computed exact
;;; integers can grow beyond the source domain; budgets stop such a solve as
;;; failure and must never be read as evidence of completed closure.
(def (relational-source name arity rows)
  (relational-owned-source name arity (relational-copy-rows rows arity)))

;;; Private constructor for rows freshly copied by this module. Core admission
;;; still checks field predicates; only the redundant ownership copy is skipped.
;; : (-> SourceName Arity OwnedScalarRows Relation)
(def (relational-owned-source name arity rows)
  ;; Retain the scalar restriction on later source replacement and on
  ;; derived rows.  The relation constructor already checks every row.
  (gerbil-ascent-relation
   name arity rows
   gerbil-ascent-hash-index-provider
   gerbil-ascent-set-storage-provider
   (make-list arity relational-scalar?)))


;;; Finite domains are inert declarations. Admission rebuilds membership
;;; predicates from copied atoms instead of retaining incoming callbacks.
(def (relational-domain-copy arity domains)
  (unless (and (list? domains) (= (length domains) arity))
    (error "finite domain column count mismatch"))
  (map (lambda (atoms)
         (unless (and (list? atoms) (<= (length atoms) 4096)
                      (andmap relational-scalar? atoms))
           (error "invalid finite scalar domain"))
         (map identity atoms)) domains))

(def (relational-domain-predicates domains)
  (map (lambda (atoms) (lambda (value) (and (member value atoms) #t))) domains))

(def (relational-finite-source name arity rows domains)
  (let (copied (relational-domain-copy arity domains))
    (gerbil-ascent-relation name arity (relational-copy-rows rows arity)
     gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider
     (relational-domain-predicates copied) (vector 'finite-domain copied))))

(def (relational-finite-lattice name arity rows mode domains)
  (unless (> arity 0) (error "finite lattice needs a value column"))
  (let (copied (relational-domain-copy arity domains))
    (unless (andmap exact-integer? (last copied))
      (error "finite lattice value domain must contain exact integers"))
    (gerbil-ascent-lattice name arity (relational-copy-rows rows arity)
     (relational-lattice-join mode) gerbil-ascent-hash-index-provider
     (relational-domain-predicates copied) (vector 'lattice mode)
     (vector 'finite-domain copied))))

;;; Lattice joins are chosen by a closed descriptor and rebuilt during
;;; admission. The last column is an exact integer; keys stay scalar.
(def (relational-lattice-join mode)
  (relational-stable
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
    (else (error "unknown checked lattice join" mode)))))

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
     (list (relational-owned-source
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

;;; Emit one short parameter-spine check and a direct operator application.
;;; A variadic case-lambda fallback introduces length/apply dispatch on this
;;; toolchain; the explicit match retains the original mismatch diagnostic.
(defrule (checked-call (parameter ...) body)
  (lambda values
    (match values
      ([parameter ...] body)
      (_ (error "relational operator argument mismatch")))))

;;; Operator arity and operand shape have already been checked. Specialize
;;; their calling convention once; literal-only operations still execute at
;;; row time so numeric errors retain their original evaluation boundary.
(def (relational-operator-call operation-procedure operands)
  (relational-stable
  (match operands
    ([operand]
     (if (eq? (vector-ref operand 0) 'variable)
       (checked-call (value) (operation-procedure value))
       (let (value (vector-ref operand 1))
         (checked-call () (operation-procedure value)))))
    ([left right]
     (if (eq? (vector-ref left 0) 'variable)
       (if (eq? (vector-ref right 0) 'variable)
         (checked-call (a b) (operation-procedure a b))
         (let (b (vector-ref right 1))
           (checked-call (a) (operation-procedure a b))))
       (let (a (vector-ref left 1))
         (if (eq? (vector-ref right 0) 'variable)
           (checked-call (b) (operation-procedure a b))
           (let (b (vector-ref right 1))
             (checked-call () (operation-procedure a b)))))))
    (_ (error "unsupported relational operator arity")))))

(def (relational-term-fingerprint terms)
  (map (lambda (term)
         (cons (.ref term 'kind) (.ref term 'value)))
       terms))

;;; Fixed reducers consume a completed lower stratum. A procedure stored
;;; in a caller-owned Aggregate is never accepted on its own authority.
(def (relational-reducer-procedure mode inputs)
  (relational-stable
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
    (else (error "unknown checked reducer" mode)))))

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
