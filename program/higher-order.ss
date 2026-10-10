;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Typed higher-order descriptors normalize to the existing positive IR.
;;; Builders run once during construction; admitted solves hold no callbacks.
(import (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-construct-inert-program)
        (only-in :gerbil-ascent/program/finite-arithmetic
                 relational-capped-product relational-capped-power)
        (only-in :gerbil-ascent/program/operator
                 relational-op-source relational-op-union relational-op-join
                 relational-op-project relational-op-select-eq relational-op-flatmap
                 relational-op-fix relational-op-compile relational-op-compiler relational-op-kind)
        (only-in :gerbil-ascent/program/scheme-checked
                 relational-scalar? relational-copy-rows relational-finite-rows relational-finite-source)
        (only-in :std/list/list delete-duplicates/hash take))

(export relational-relation-type relational-arrow-type relational-type?
        relational-type=? relational-type-height-expression
        relational-type-kind relational-type-left relational-type-right
        relational-typed-term-kind relational-typed-term-inputs relational-typed-term-data
        relational-typed-source relational-typed-function relational-typed-apply
        relational-typed-union relational-typed-join relational-typed-project
        relational-typed-select-eq relational-typed-flatmap relational-typed-fix
        relational-typed-term? relational-typed-term-type relational-typed-compile)

;; Relation fields hold arity/domain; arrow fields hold input/output types.
;; : (forall (a b) (-> Symbol a b (Type (Variant a b))))
;; : (-> TypeKind TypeLeft TypeRight FiniteType)
(defstruct relational-type (kind left right))
;; : (forall (a c d) (-> (Type a) Symbol [(Term c)] d (Term a)))
;; : (-> FiniteType TermKind Children TermData TypedTerm)
(defstruct relational-typed-term (type kind inputs data))
;; Lexical bindings use descriptor identity, never source-name equality.
;; : (forall (a b c d) (-> (Term a) (Term b) [(Pair (Term c) d)] (Closure a b)))
;; : (-> ParameterTerm BodyTerm LexicalEnvironment ReifiedClosure)
(defstruct typed-closure (parameter body environment))

;; Own the domain spine; its scalar elements have stable equality and hashing.
;; : (forall (a) (-> Integer [a] (Type [a])))
;; : (-> Arity FiniteScalarDomain FiniteRelationType)
(def (relational-relation-type arity atoms)
  (unless (and (exact-integer? arity) (<= 0 arity 128)
               (list? atoms) (<= (length atoms) 4096)
               (andmap relational-scalar? atoms))
    (error "invalid finite relation type"))
  (make-relational-type 'relation arity (delete-duplicates/hash (map values atoms))))

;; : (forall (a b) (-> (Type a) (Type b) (Type (-> a b))))
;; : (-> FiniteType FiniteType FiniteArrowType)
(def (relational-arrow-type input output)
  (unless (and (relational-type? input) (relational-type? output))
    (error "invalid finite arrow type"))
  (make-relational-type 'arrow input output))

;; Relation equality compares domain membership, independent of atom order.
;; Type candidates are untrusted inputs; non-descriptors compare false.
;;; The public descriptor exposes mutable domain spines. Build comparison
;;; indexes for this call only; equal ordered domains need no table at all.
;;; Keep the original length-and-support behavior even for mutated duplicates.
;; : (-> ScalarDomain ScalarDomain Boolean)
(def (same-domain-atoms? left right)
  (and (= (length left) (length right))
       (or (equal? left right)
           (let (members (make-hash-table))
             (for-each (lambda (atom) (hash-put! members atom #t)) right)
             (andmap (lambda (atom) (and (hash-get members atom) #t)) left)))))

;; : (forall (a b) (-> a b Boolean))
;; : (-> TypeCandidate TypeCandidate Boolean)
(def (relational-type=? left right)
  (and (relational-type? left) (relational-type? right)
       (or (eq? left right)
       (and (eq? (relational-type-kind left) (relational-type-kind right))
       (case (relational-type-kind left)
         ((relation)
          (and (= (relational-type-left left) (relational-type-left right))
               (same-domain-atoms? (relational-type-right left)
                                   (relational-type-right right))))
         ((arrow)
          (and (relational-type=? (relational-type-left left) (relational-type-left right))
               (relational-type=? (relational-type-right left) (relational-type-right right))))
         (else #f))))))

;;; Copy validated finite types, preserving graph identity and canonical domains.
;;; The charge hook shares the compiler's actual expansion counter; public
;;; height analysis uses the same shape/cycle/depth admission without a counter.
(def (finite-type-snapshotter charge!)
  (let (copies (make-hash-table-eq))
    (def (snapshot type path)
      (charge!)
      (unless (and (relational-type? type) (not (memq type path)) (< (length path) 128))
        (error "invalid or cyclic finite type"))
      (or (hash-get copies type)
          (let (owned
                (case (relational-type-kind type)
                  ((relation) (relational-relation-type (relational-type-left type)
                                                        (relational-type-right type)))
                  ((arrow) (relational-arrow-type
                            (snapshot (relational-type-left type) (cons type path))
                            (snapshot (relational-type-right type) (cons type path))))
                  (else (error "unknown finite type"))))
            (hash-put! copies type owned)
            owned)))
    snapshot))

;;; Type structure owns the finite lattice formulas. The arithmetic supplied
;;; by the caller either records expressions or saturates at a budget cap.
;; : (forall (a) (-> (Type a) (-> SExpression SExpression SExpression) SExpression))
;; : (-> FiniteType CardinalityPower Cardinality)
(def (type-cardinality type power (cache (make-hash-table-eq)))
  (or (hash-get cache type)
      (let (value
            (case (relational-type-kind type)
              ((relation) (power 2 (power (length (relational-type-right type))
                                        (relational-type-left type))))
              ((arrow) (power (type-cardinality (relational-type-right type) power cache)
                              (type-cardinality (relational-type-left type) power cache)))
              (else (error "unknown finite type"))))
        (hash-put! cache type value) value)))

;; : (forall (a) (-> (Type a) (-> SExpression SExpression SExpression) (-> SExpression SExpression SExpression) SExpression))
;; : (-> FiniteType CardinalityPower HeightProduct Height)
(def (type-height type power multiply (cardinalities (make-hash-table-eq)) (heights (make-hash-table-eq)))
  (unless (relational-type? type) (error "expected finite type"))
  (or (hash-get heights type)
      (let (value
            (case (relational-type-kind type)
              ((relation) (power (length (relational-type-right type))
                                (relational-type-left type)))
              ((arrow) (multiply (type-cardinality (relational-type-left type) power cardinalities)
                                 (type-height (relational-type-right type) power multiply cardinalities heights)))
              (else (error "unknown finite type"))))
        (hash-put! heights type value) value)))

;;; Symbolic heights avoid constructing enormous powerset/function spaces.
;; : (forall (a) (-> (Type a) SExpression))
;; : (-> FiniteType SymbolicHeight)
(def (relational-type-height-expression type)
  (type-height ((finite-type-snapshotter void) type [])
               (lambda (base exponent) (list 'expt base exponent))
               (lambda (left right) (list '* left right))))

;; : (forall (a) (-> (Term [a]) (Type [a])))
;; : (-> TypedRelationTerm FiniteRelationType)
(def (relation-term-type term)
  (unless (and (relational-typed-term? term)
               (eq? (relational-type-kind (relational-typed-term-type term)) 'relation))
    (error "expected a typed relation"))
  (relational-typed-term-type term))

;; : (forall (a b) (-> (Type [a]) (Type [b]) Boolean))
;; : (-> FiniteRelationType FiniteRelationType Boolean)
(def (same-domain? left right)
  (let ((a (relational-type-right left)) (b (relational-type-right right)))
    ;; This check formerly constructed two throwaway nullary type objects.
    ;; Retain left-to-right scalar/size admission, then compare canonical
    ;; supports directly. Domain duplicates are allowed at this boundary.
    (for-each (lambda (atoms)
                (unless (and (list? atoms) (<= (length atoms) 4096)
                             (andmap relational-scalar? atoms))
                  (error "invalid finite relation type"))) (list a b))
    (or (equal? a b)
        (let ((seen-left (make-hash-table)) (seen-right (make-hash-table)))
          (for-each (lambda (atom) (hash-put! seen-left atom #t)) a)
          (for-each (lambda (atom) (hash-put! seen-right atom #t)) b)
          (and (= (hash-length seen-left) (hash-length seen-right))
               (andmap (lambda (atom) (and (hash-get seen-right atom) #t)) a))))))

;; : (forall (a) (-> (Type [a]) [[a]] Void))
;; : (-> FiniteRelationType Rows Void)
(def (check-domain! type rows (start 0) (width (relational-type-left type)))
  ;; Select membership once for the entire admitted segment. Small checks
  ;; retain the list path; large row batches amortize a local equality index.
  ;; Public domain spines are mutable: never retain this index across calls.
  (def domain (relational-type-right type))
  (def contains?
    (if (and (> (length domain) 16) (> (* (length rows) width) 16))
      (let (members (make-hash-table))
        (for-each (lambda (atom) (hash-put! members atom #t)) domain)
        (cut hash-get members <>))
      (cut member <> domain)))
  (for-each (lambda (row)
              ;; Owned rows already have admitted arities. Inspect a bounded
              ;; segment directly rather than allocating prefix/suffix lists.
              (let (segment (list-tail row start))
                (let walk ((rest segment) (remaining width))
                  (unless (zero? remaining)
                    (unless (contains? (car rest))
                      (error "typed relation value outside declared domain" (car rest)))
                    (walk (cdr rest) (- remaining 1)))))) rows))

;; Freeze caller-owned row spines and check every atom against the domain.
;; : (forall (a) (-> Symbol (Type [a]) [[a]] (Term [a])))
;; : (-> SourceName FiniteRelationType Rows TypedRelationTerm)
(def (relational-typed-source name type rows)
  (unless (and (symbol? name) (relational-type? type)
               (eq? (relational-type-kind type) 'relation))
    (error "invalid typed source"))
  (let (owned (relational-copy-rows rows (relational-type-left type)))
    (check-domain! type owned)
    (make-relational-typed-term type 'source [] (vector name owned))))

;; Invoke the builder once. Retain its descriptor and binder, not the callback.
;; : (forall (a b) (-> (Type a) (-> (Term a) (Term b)) (Term (-> a b))))
;; : (-> FiniteType DescriptorBuilder TypedFunctionTerm)
(def (relational-typed-function input builder)
  (unless (and (relational-type? input) (procedure? builder))
    (error "invalid typed function builder"))
  (let* ((parameter (make-relational-typed-term input 'parameter [] #f))
         (body (builder parameter)))
    (unless (relational-typed-term? body) (error "typed function body is not a descriptor"))
    (make-relational-typed-term (relational-arrow-type input (relational-typed-term-type body))
                                'function (list body) parameter)))

;; : (forall (a b) (-> (Term (-> a b)) (Term a) (Term b)))
;; : (-> TypedFunctionTerm TypedTerm TypedTerm)
(def (relational-typed-apply function argument)
  (unless (and (relational-typed-term? function) (relational-typed-term? argument)
               (eq? (relational-type-kind (relational-typed-term-type function)) 'arrow)
               (relational-type=? (relational-type-left (relational-typed-term-type function))
                                   (relational-typed-term-type argument)))
    (error "typed function application signature mismatch"))
  (make-relational-typed-term (relational-type-right (relational-typed-term-type function))
                              'apply (list function argument) #f))

;; : (forall (a) (-> (Term [a]) (Term [a]) (Term [a])))
;; : (-> TypedRelationTerm TypedRelationTerm TypedRelationTerm)
(def (relational-typed-union left right)
  (let ((lt (relation-term-type left)) (rt (relation-term-type right)))
    (unless (relational-type=? lt rt) (error "typed union signature mismatch"))
    (make-relational-typed-term lt 'union (list left right) #f)))

;; : (forall (a) (-> (Term [a]) (Term [a]) Integer Integer (Term [a])))
;; : (-> TypedRelationTerm TypedRelationTerm Column Column TypedRelationTerm)
(def (relational-typed-join left right left-key right-key)
  (let ((lt (relation-term-type left)) (rt (relation-term-type right)))
    (unless (and (same-domain? lt rt)
                 (exact-integer? left-key) (<= 0 left-key) (< left-key (relational-type-left lt))
                 (exact-integer? right-key) (<= 0 right-key) (< right-key (relational-type-left rt)))
      (error "typed join signature mismatch"))
    (make-relational-typed-term
     (relational-relation-type (+ (relational-type-left lt) (relational-type-left rt))
                               (relational-type-right lt))
     'join (list left right) (vector left-key right-key))))

;; : (forall (a) (-> (Term [a]) [Integer] (Term [a])))
;; : (-> TypedRelationTerm Columns TypedRelationTerm)
(def (relational-typed-project input columns)
  (let (type (relation-term-type input))
    (unless (and (list? columns)
                 (andmap (lambda (column) (and (exact-integer? column) (<= 0 column)
                                              (< column (relational-type-left type)))) columns))
      (error "typed projection column outside signature"))
    (make-relational-typed-term
     (relational-relation-type (length columns) (relational-type-right type))
     'project (list input) (map values columns))))

;; : (forall (a) (-> (Term [a]) Integer a (Term [a])))
;; : (-> TypedRelationTerm Column Scalar TypedRelationTerm)
(def (relational-typed-select-eq input column value)
  (let (type (relation-term-type input))
    (unless (and (exact-integer? column) (<= 0 column) (< column (relational-type-left type))
                 (member value (relational-type-right type)))
      (error "typed selection outside declared domain/signature"))
    (make-relational-typed-term type 'select-eq (list input) (vector column value))))

;; : (forall (a b) (-> (Term [a]) (Type [b]) [(Tuple [a] [b])] (Term [b])))
;; : (-> TypedRelationTerm FiniteRelationType FiniteMapping TypedRelationTerm)
(def (relational-typed-flatmap input output-type entries)
  (let ((it (relation-term-type input)))
    (unless (and (relational-type? output-type)
                 (eq? (relational-type-kind output-type) 'relation))
      (error "typed finite mapping output must be a relation"))
    (let* ((width (relational-type-left it))
           (table (relational-finite-rows width (relational-type-left output-type) entries)))
      ;; All input-domain failures still precede every output-domain failure.
      (check-domain! it table 0 width)
      (check-domain! output-type table width)
      (make-relational-typed-term output-type 'flatmap (list input) (vector width table)))))

;; : (forall (a) (-> (Term (-> a a)) (Term a)))
;; : (-> TypedEndofunctionTerm TypedTerm)
(def (relational-typed-fix function)
  (unless (and (relational-typed-term? function)
               (eq? (relational-type-kind (relational-typed-term-type function)) 'arrow))
    (error "typed fix requires a function descriptor"))
  (let* ((signature (relational-typed-term-type function))
         (input (relational-type-left signature)) (output (relational-type-right signature)))
    (unless (relational-type=? input output)
      (error "typed fix requires an endofunction on a finite type"))
    (make-relational-typed-term input 'fix (list function) #f)))

;;; Normalization is a compiler phase with a real expansion budget. Every
;;; source is rechecked; lexical parameter lookup rejects escaped captures.
;;; Functions are data closures, and application is beta lowering into one IR.
;; Every invocation owns its counters, source tables and domain accumulator.
;; Revalidate the complete descriptor graph before lowering. Count every type,
;; scoped term and lowering visit; cached type graphs charge each lookup.
;; Preserve lexical environments by reifying functions as closures. Relation
;; fixed points lower to IR; function fixed points use the conservative finite
;; height with saturating arithmetic, never sample-based early termination.
;; ExpansionLimit is optional at the call site and defaults to 10000.
;; : (forall (a p n) (-> (Term [a]) Integer Integer Integer Integer (Values p n)))
;; : (-> TypedRelationTerm InputLimit DerivedLimit OutputLimit ExpansionLimit (Values Program OutputName))
(def (relational-typed-compile term input-limit derived-limit output-limit (expansion-limit 10000))
  (relation-term-type term)
  (unless (and (exact-integer? expansion-limit) (> expansion-limit 0))
    (error "typed expansion limit must be positive"))
  (let ((steps 0) (sources (make-hash-table-eq)) (source-domains (make-hash-table-eq))
        (atoms []) (domain-chunks []))
    (def term-copies (make-hash-table-eq))
    (def (charge!)
      (set! steps (+ steps 1))
      (when (> steps expansion-limit) (error "typed normalization budget exceeded")))
    (def snapshot-type (finite-type-snapshotter charge!))
    (def collected-types (make-hash-table-eq))
    (def (collect-type-atoms! type)
      (unless (hash-get collected-types type)
        (hash-put! collected-types type #t)
        (case (relational-type-kind type)
          ((relation) (set! domain-chunks (cons (relational-type-right type) domain-chunks)))
          ((arrow) (collect-type-atoms! (relational-type-left type))
                   (collect-type-atoms! (relational-type-right type))))))
    (def (check-type! type)
      (let (owned (snapshot-type type []))
        (collect-type-atoms! owned)
        owned))
    ;; A copy is reusable only after this occurrence's children and type have
    ;; passed admission. Identity binds frozen types/children; structural data
    ;; equality binds caller row/column spines to their admitted owned copy.
    ;; Parameters always enter the constructor's lexical binding check.
    (def (checked-copy node type kind inputs data)
      (let (owned (hash-get term-copies node))
        (and owned (not (eq? kind 'parameter))
             (with ((relational-typed-term prior-type prior-kind prior-inputs prior-data) owned)
               (and (eq? type prior-type) (eq? kind prior-kind)
                    (= (length inputs) (length prior-inputs))
                    (andmap eq? inputs prior-inputs)
                    (equal? data prior-data)
                    owned)))))
    ;; Reconstruction owns constructor contracts; traversal owns lexical
    ;; admission, path checks and per-occurrence accounting before any reuse.
    (def (rebuild-term node scope type kind inputs data)
      (case kind
        ((parameter)
         (let (binding (assq node scope))
           (unless (and binding (null? inputs) (relational-type=? (cdr binding) type))
             (error "typed parameter outside admitted lexical scope"))
           (make-relational-typed-term type 'parameter [] #f)))
        ((source)
         (unless (and (null? inputs) (vector? data) (= (vector-length data) 2))
           (error "invalid typed source data"))
         (relational-typed-source (vector-ref data 0) type (vector-ref data 1)))
        ((apply)
         (unless (= (length inputs) 2) (error "invalid typed application children"))
         (relational-typed-apply (car inputs) (cadr inputs)))
        ((fix)
         (unless (= (length inputs) 1) (error "invalid typed fix children"))
         (relational-typed-fix (car inputs)))
        ((union)
         (unless (= (length inputs) 2) (error "invalid typed union children"))
         (relational-typed-union (car inputs) (cadr inputs)))
        ((join)
         (unless (and (= (length inputs) 2) (vector? data) (= (vector-length data) 2))
           (error "invalid typed join data"))
         (relational-typed-join (car inputs) (cadr inputs) (vector-ref data 0) (vector-ref data 1)))
        ((project)
         (unless (= (length inputs) 1) (error "invalid typed project children"))
         (relational-typed-project (car inputs) data))
        ((select-eq)
         (unless (and (= (length inputs) 1) (vector? data) (= (vector-length data) 2))
           (error "invalid typed selection data"))
         (relational-typed-select-eq (car inputs) (vector-ref data 0) (vector-ref data 1)))
        ((flatmap)
         (unless (and (= (length inputs) 1) (vector? data) (= (vector-length data) 2)
                      (= (vector-ref data 0) (relational-type-left (relation-term-type (car inputs)))))
           (error "invalid typed mapping data"))
         (relational-typed-flatmap
          (car inputs) type
          (map (lambda (row) (list (take row (vector-ref data 0))
                                  (list-tail row (vector-ref data 0)))) (vector-ref data 1))))
        (else (error "unsupported typed term kind"))))
    (def (check-term! node scope path)
      (charge!)
      (unless (and (relational-typed-term? node) (not (memq node path)) (< (length path) 128))
        (error "invalid or cyclic typed term"))
      (let ((type (check-type! (relational-typed-term-type node)))
            (kind (relational-typed-term-kind node))
            (inputs (relational-typed-term-inputs node))
            (data (relational-typed-term-data node)))
        (unless (and (list? inputs) (<= (length inputs) 2)) (error "invalid typed children"))
        (if (eq? kind 'function)
          (begin
            (unless (and (= (length inputs) 1) (eq? (relational-type-kind type) 'arrow)
                         (relational-typed-term? data)
                         (eq? (relational-typed-term-kind data) 'parameter))
              (error "typed function binder/signature mismatch"))
            (let* ((bound-scope (cons (cons data (relational-type-left type)) scope))
                   (parameter (check-term! data bound-scope (cons node path)))
                   (body (check-term! (car inputs) bound-scope (cons node path))))
              (unless (relational-type=? (relational-typed-term-type body) (relational-type-right type))
                (error "typed function result signature mismatch"))
              (or (hash-get term-copies node)
                  (let (owned (make-relational-typed-term type 'function (list body) parameter))
                    (hash-put! term-copies node owned) owned))))
          (begin
            (when (memq kind '(parameter apply fix union))
              (unless (eq? data #f) (error "invalid typed inert node data")))
            (let* ((inputs (map (lambda (input) (check-term! input scope (cons node path))) inputs))
                   (rebuilt (or (checked-copy node type kind inputs data)
                                (rebuild-term node scope type kind inputs data))))
              ;; Same-named source observations still publish in visit order,
              ;; even when this occurrence reuses its owned representation.
              (when (eq? kind 'source)
                (hash-put! source-domains (vector-ref data 0) (relational-type-right type)))
              (unless (relational-type=? (relational-typed-term-type rebuilt) type)
                (error "typed node result signature mismatch"))
              (or (hash-get term-copies node)
                  (begin (hash-put! term-copies node rebuilt) rebuilt)))))))
    (def (apply-closure closure argument)
      (unless (typed-closure? closure) (error "typed application is not a reified function"))
      (lower (typed-closure-body closure)
             (cons (cons (typed-closure-parameter closure) argument)
                   (typed-closure-environment closure))))
    ;; Arrow lattices have pointwise order and a constant-bottom least element.
    ;; Unroll from bottom for the full conservative height, never until an
    ;; observed sample happens to agree. All arithmetic saturates before huge
    ;; function-space cardinalities can allocate enormous exact integers.
    (def (bounded-height type)
      (let (cap (+ expansion-limit 1))
        (type-height type
                     (lambda (base exponent) (relational-capped-power cap base exponent))
                     (lambda (left right) (relational-capped-product cap left right)))))
    (def (bottom-term type)
      (case (relational-type-kind type)
        ((relation)
         (let (name (gensym 'typed-bottom))
           (hash-put! source-domains name (relational-type-right type))
           (relational-typed-source name type [])))
        ((arrow) (relational-typed-function
                  (relational-type-left type)
                  (lambda (_) (bottom-term (relational-type-right type)))))))
    (def (lower node environment)
      (charge!)
      (unless (relational-typed-term? node) (error "invalid typed term"))
      (with ((relational-typed-term type kind inputs data) node)
        (case kind
          ((source)
           (or (hash-get sources node)
               ;; check-term! already froze and domain-checked these rows.
               ;; The positive operator constructor performs its ownership
               ;; copy; lowering need not rebuild a second typed descriptor.
               (let (op (relational-op-source (vector-ref data 0) (relational-type-left type)
                                              (vector-ref data 1)))
                 (hash-put! sources node op) op)))
          ((parameter) (let (binding (assq node environment))
                         (unless binding (error "typed parameter missing from frozen environment")) (cdr binding)))
          ((function) (make-typed-closure data (car inputs) environment))
          ((apply) (apply-closure (lower (car inputs) environment)
                                  (lower (cadr inputs) environment)))
          ((fix)
           (let (closure (lower (car inputs) environment))
             (if (eq? (relational-type-kind type) 'relation)
               (relational-op-fix (relational-type-left type)
                 (lambda (parameter) (apply-closure closure parameter)))
               (let (height (bounded-height type))
                 (when (> height (- expansion-limit steps))
                   (error "typed function fixed-point height exceeds normalization budget"))
                 (let loop ((remaining height) (value (lower (bottom-term type) [])))
                   (if (zero? remaining) value
                     (loop (- remaining 1) (apply-closure closure value))))))))
          ((union) (relational-op-union (lower (car inputs) environment)
                                        (lower (cadr inputs) environment)))
          ((join) (relational-op-join (lower (car inputs) environment)
                                      (lower (cadr inputs) environment)
                                      (vector-ref data 0) (vector-ref data 1)))
          ((project) (relational-op-project (lower (car inputs) environment) data))
          ((select-eq) (relational-op-select-eq (lower (car inputs) environment)
                                               (vector-ref data 0) (vector-ref data 1)))
          ((flatmap) (relational-op-flatmap
                      (lower (car inputs) environment) (relational-type-left type)
                      (map (lambda (row) (list (take row (vector-ref data 0))
                                              (list-tail row (vector-ref data 0)))) (vector-ref data 1))))
          (else (error "unsupported typed term kind")))))
    (set! term (check-term! term [] []))
    ;; Domains are inert and every collection visit has already been charged.
    ;; Flatten once in original visitation order. Gerbil's default duplicate
    ;; removal keeps the last occurrence, which is observable in published
    ;; domains; a first-occurrence set accumulator would change that order.
    (for-each (lambda (domain) (set! atoms (append domain atoms))) domain-chunks)
    (set! atoms (delete-duplicates/hash atoms))
    ;; Native source observations retain occurrence multiplicity and budgets.
    ;; A typed relation denotes a set even when lowering returns a bare source
    ;; (including a parameter or function bottom). Materialize its identity
    ;; projection as a derived relation; never deduplicate the source log.
    (let* ((root (lower term []))
           (result-root
            (if (eq? (relational-op-kind root) 'source)
              (relational-op-project root (iota (relational-type-left (relational-typed-term-type term))))
              root)))
    ;; Emit the final finite-domain representation directly. Constructing an
    ;; ordinary program and rebuilding all relations repeated contract checks
    ;; and ownership copies without changing the lowered rules or handles.
    ;; Typed admission and lowering have frozen the entire inert graph. Use
    ;; the existing private construction extent, then recursively validate the
    ;; complete Program outside that extent before either value escapes.
    (gerbil-ascent-construct-inert-program
     (lambda ()
       (relational-op-compile result-root input-limit derived-limit output-limit
        (.o (:: @ relational-op-compiler)
            (.make-relation
             (lambda (name arity rows)
               (let (domain (or (hash-get source-domains name) atoms))
                 (relational-finite-source name arity rows
                                          (make-list arity domain))))))))))))
