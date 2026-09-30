;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; First executable gate for the proposed Scheme relational language.
;;; This module is intentionally separate from the old Ascent surface: it
;;; accepts positive scalar rules, with no host callbacks in recursion.
(import "objects.ss"
        (only-in "types.ss" GerbilAscentFragmentContract
                 GerbilAscentProgramContract)
        (only-in "evaluate.ss" gerbil-ascent-make-engine)
        (only-in "session.ss" gerbil-ascent-open-session
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in :std/list/list append-map find)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-set-storage-provider))

(export relational-program relational-fragment relational-compose
        relational-export relational-admit relational-solve
        relational-query relational-query-name relational-open-session
        relational-session-replace-source! relational-session-run
        relational-open-program-session
        relational-program-replace-source!
        relational-program-session-run relational-program-query)

;;; The native Gerbil values keep an admitted engine and completed result
;;; opaque to clients. Only the functions below cross each lifecycle edge.
(defstruct relational-admission (run))
(defstruct relational-solution (result))
(defstruct relational-session (engine source-arities))
(defstruct relational-program-session (engine source-arities))
(defstruct relational-program-solution (result))

;;; Restrict sources and results to immutable scalar atoms. Computed exact
;;; integers can grow beyond the source domain; budgets stop such a solve as
;;; failure and must never be read as evidence of completed closure.
(def (relational-atom-value? value)
  (or (exact-integer? value) (boolean? value) (symbol? value) (char? value)))

(def (relational-source name arity rows)
  ;; Retain the scalar restriction on later source replacement and on
  ;; derived rows.  The relation constructor already checks every row.
  (gerbil-ascent-relation
   name arity rows
   gerbil-ascent-hash-index-provider
   gerbil-ascent-set-storage-provider
   (make-list arity relational-atom-value?)))

;;; Logic variables are visibly distinct from lexical Scheme identifiers.
;;; Plain symbols and computed terms are excluded from this first gate.
(defsyntax (relational-term stx)
  (syntax-case stx ()
    ((_ term)
     (identifier? (syntax term))
     (let* ((datum (syntax->datum (syntax term)))
            (spelling (symbol->string datum)))
       (cond
        ((eq? datum '?_)
         (syntax (gerbil-ascent-wildcard)))
        ((and (> (string-length spelling) 1)
              (char=? (string-ref spelling 0) #\?))
         (syntax (gerbil-ascent-variable 'term)))
        (else
         (raise-syntax-error
          #f "relational term must be a ?variable or scalar literal"
          (syntax term))))))
    ((_ term)
     (let (datum (syntax->datum (syntax term)))
       (if (or (exact-integer? datum) (boolean? datum)
               (char? datum))
         (syntax (gerbil-ascent-literal term))
         (raise-syntax-error
          #f "relational term must be an immutable scalar literal"
          (syntax term)))))))

;;; Boundary: A program-level atom names a relation in the assembled graph.
;;; Invariant: Its terms are lowered through the restricted scalar grammar.
(defsyntax (relational-atom stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-atom 'name
                               (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational atom" (syntax bad)))))

;;; Fragment atoms use Scheme-bound relation handles.  Each source/private
;;; binding below is evaluated on each constructor call, not at macro expansion.
(defsyntax (relational-atom/lexical stx)
  (syntax-case stx ()
    ((_ (name term ...))
     (identifier? (syntax name))
     (syntax (gerbil-ascent-atom name
                               (list (relational-term term) ...))))
    ((_ bad)
     (raise-syntax-error #f "expected a relational atom" (syntax bad)))))

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
  (let (inputs (map identity variables))
    (gerbil-ascent-guard
     inputs
     (relational-operator-procedure 'where operation (length inputs))
     (vector 'where operation (map identity inputs)))))

(def (relational-compute output operation variables)
  (let (inputs (map identity variables))
    (gerbil-ascent-binding
     output inputs
     (relational-operator-procedure 'compute operation (length inputs))
     (vector 'compute operation (map identity inputs) output))))

;;; Both public forms share this rule-body grammar. The supplied atom
;;; lowering chooses quoted program names or lexical fragment handles;
;;; scalar operators keep one validation and descriptor path.
(defsyntax (relational-checked-clause stx)
  (def (logic-variable? input)
    (and (identifier? input)
         (let* ((datum (syntax->datum input))
                (spelling (symbol->string datum)))
           (and (not (eq? datum '?_))
                (> (string-length spelling) 1)
                (char=? (string-ref spelling 0) #\?)))))
  (syntax-case stx (where compute)
    ((_ atom-lowering (where (operation input ...)))
     (and (identifier? (syntax operation))
          (andmap logic-variable? (syntax->list (syntax (input ...)))))
     (syntax (relational-where 'operation '(input ...))))
    ((_ atom-lowering (compute output (operation input ...)))
     (and (logic-variable? (syntax output))
          (identifier? (syntax operation))
          (andmap logic-variable? (syntax->list (syntax (input ...)))))
     (syntax (relational-compute 'output 'operation '(input ...))))
    ((_ atom-lowering (name term ...))
     (and (identifier? (syntax atom-lowering))
          (identifier? (syntax name))
          (not (memq (syntax->datum (syntax name)) '(where compute))))
     (syntax (atom-lowering (name term ...))))
    ((_ atom-lowering bad)
     (raise-syntax-error #f "expected atom, where, or compute clause"
                         (syntax bad)))))

;;; Boundary: This collector fixes clause order and requires a final budget.
;;; Invariant: Declarations and rules remain inspectable before evaluation.
(defsyntax (relational-collect stx)
  (syntax-case stx (relation rule limits)
    ((_ (declared ...) (lowered ...)
        (relation name (column ...) rows) rest ...)
     (and (identifier? (syntax name))
          (andmap identifier? (syntax->list (syntax (column ...)))))
     (syntax (relational-collect
              (declared ...
                        (relational-source
                         'name (length '(column ...)) rows))
              (lowered ...) rest ...)))
    ((_ (declared ...) (lowered ...)
        (relation name (column ...)) rest ...)
     (and (identifier? (syntax name))
          (andmap identifier? (syntax->list (syntax (column ...)))))
     (syntax (relational-collect
              (declared ...
                        (relational-source
                         'name (length '(column ...)) []))
              (lowered ...) rest ...)))
    ((_ (declared ...) (lowered ...) (rule head body ...) rest ...)
     (syntax (relational-collect
              (declared ...)
              (lowered ...
                       (gerbil-ascent-rule
                        (list (relational-atom head))
                        (list (relational-checked-clause
                               relational-atom body) ...)))
              rest ...)))
    ((_ (declared ...) (lowered ...) (limits input derived output))
     (syntax (let (relations (list declared ...))
               (gerbil-ascent-program
                relations (list lowered ...) input derived output
                (map (lambda (relation) (.ref relation 'name))
                     relations)))))
    ((_ (declared ...) (lowered ...) bad rest ...)
     (raise-syntax-error
      #f "expected relation, rule, or final limits clause"
      (syntax bad)))
    ((_ (declared ...) (lowered ...))
     (raise-syntax-error
      #f "relational-program requires a final limits clause" stx))))

;; relational-program
;;   : (-> Syntax CheckedPositiveProgramExpression)
;;   | doc m%
;;       Build a checked positive program. Source and derived values are
;;       immutable scalar atoms. Rules admit only fixed checked scalar
;;       operators, not host closures or plain Scheme identifiers. The final
;;       limits clause supplies resource-failure bounds.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-program
;;         (relation edge (from to) '((1 2)))
;;         (relation path (from to))
;;         (rule (path ?x ?y) (edge ?x ?y))
;;         (limits 4 4 8))
;;       ;; => a program value; evaluating it derives path(1, 2)
;;       ```
;;     %
;;; Boundary: This frame lowers only syntax with inspectable rule dependencies.
;;; Source expressions stay lexical while rules reject host calls.
;;; Invariant: Evaluation cannot observe an undeclared changing relation.
(defsyntax (relational-program stx)
  (syntax-case stx ()
    ((_ clause ...)
     (syntax (relational-collect () () clause ...)))))

;; relational-fragment
;;   : (-> Syntax FirstClassFragmentExpression)
;;   | doc m%
;;       Instantiate a positive fragment with fresh source and private
;;       predicate names. Imports are existing relation handles. Named
;;       exports are recorded on the existing typed POO fragment value.
;;
;;       # Examples
;;
;;       ```scheme
;;       (relational-fragment
;;         (import)
;;         (source (edge (from to) '((1 2))))
;;         (private (path (from to)))
;;         (export (reach path))
;;         (rule (path ?x ?y) (edge ?x ?y)))
;;       ;; => a fragment with a reach export
;;       ```
;;     %
;;; Boundary: Imports preserve caller handles while declarations get fresh names.
;;; Invariant: Separate uses of one Scheme builder cannot alias by spelling.
;;; Final graph admission checks the assembled relation namespace.
(defrules relational-fragment (import source private export rule)
  ((_ (import (import-name imported-handle) ...)
      (source (source-name (source-column ...) source-rows) ...)
      (private (private-name (private-column ...)) ...)
      (export (public-name exported-name) ...)
      (rule (head head-term ...)
            (body body-term ...) ...) ...)
   (let ((import-name imported-handle) ...
         (source-name (gensym 'source-name)) ...
         (private-name (gensym 'private-name)) ...)
     (gerbil-ascent-fragment
      (list (relational-source source-name
                               (length '(source-column ...))
                               source-rows) ...
            (relational-source private-name
                               (length '(private-column ...))
                               []) ...)
      (list
       (gerbil-ascent-rule
        (list (relational-atom/lexical (head head-term ...)))
        (list (relational-checked-clause
               relational-atom/lexical (body body-term ...)) ...)) ...)
      (list (cons 'public-name exported-name) ...)
      (list source-name ...)))))

;;; A public label is scoped to its fragment instance, rather than to the
;;; process or composed program. Only declared labels can reveal a handle.
(def (relational-export fragment label)
  (validate GerbilAscentFragmentContract fragment)
  ((.ref fragment 'exports) label))

;;; A query observes only a completed result and a handle exported by the
;;; supplied fragment. Copy returned rows so callers cannot edit the snapshot.
(def (relational-query solution fragment label)
  (unless (relational-solution? solution)
    (error "relational query requires a solved value" solution))
  (let (result (relational-solution-result solution))
    (unless (.ref result 'finished)
      (error "relational query requires a completed result"))
    (map (lambda (row) (map identity row))
         ((.ref result 'rows-of) (relational-export fragment label)))))

;;; Named one-shot programs may contain private derived relations, so they
;;; cannot use the retained session API, which requires every relation to be
;;; source-capable. Query the completed admitted result directly.
(def (relational-query-name solution name)
  (unless (and (relational-solution? solution) (symbol? name))
    (error "relational named query requires a solved value" name))
  (let (result (relational-solution-result solution))
    (unless (.ref result 'finished)
      (error "relational named query requires a completed result"))
    (map (lambda (row) (map identity row))
         ((.ref result 'rows-of) name))))

(def (relational-program-query solution name)
  (unless (and (relational-program-solution? solution) (symbol? name))
    (error "relational program query requires a named solution" name))
  (let (result (relational-program-solution-result solution))
    (unless (.ref result 'finished)
      (error "relational program query requires a completed result"))
    (map (lambda (row) (map identity row))
         ((.ref result 'rows-of) name))))

;;; Composition is inert. Admission checks the assembled schema and rules
;;; later, after every fragment has contributed to the whole program.
(def (relational-compose fragments input-limit derived-limit output-limit)
  (for-each
   (lambda (fragment)
     (validate GerbilAscentFragmentContract fragment))
   fragments)
  (gerbil-ascent-program
   (append-map (lambda (fragment) (.ref fragment 'relations)) fragments)
   (append-map (lambda (fragment) (.ref fragment 'rules)) fragments)
   input-limit derived-limit output-limit
   (append-map (lambda (fragment) (.ref fragment 'source-handles))
               fragments)))

;;; Admission rebuilds only the checked positive grammar. This removes
;;; caller-owned row/rule lists before planning and rejects old host callbacks.
(def (relational-copy-term term)
  (case (.ref term 'kind)
    ((variable) (gerbil-ascent-variable (.ref term 'value)))
    ((wildcard) (gerbil-ascent-wildcard))
    ((literal)
     (let (value (.ref term 'value))
       (unless (relational-atom-value? value)
         (error "non-scalar relational literal" value))
       (gerbil-ascent-literal value)))
    (else (error "unsupported relational term" (.ref term 'kind)))))

(def (relational-copy-atom atom)
  (unless (eq? (.ref atom 'ascent-clause-kind) 'atom)
    (error "unsupported relational clause"))
  (gerbil-ascent-atom
   (.ref atom 'relation)
   (map relational-copy-term (.ref atom 'terms))))

;;; Rebuild from the descriptor, never from the callback stored for the old
;;; evaluator. An unmarked guard or binding cannot cross admission.
(def (relational-copy-clause clause)
  (case (.ref clause 'ascent-clause-kind)
    ((atom) (relational-copy-atom clause))
    ((guard)
     (let (descriptor (.ref clause 'checked-operator))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 3)
                    (eq? (vector-ref descriptor 0) 'where)
                    (equal? (vector-ref descriptor 2)
                            (.ref clause 'variables)))
         (error "untrusted relational filter"))
       (relational-where (vector-ref descriptor 1)
                         (vector-ref descriptor 2))))
    ((binding)
     (let (descriptor (.ref clause 'checked-operator))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 4)
                    (eq? (vector-ref descriptor 0) 'compute)
                    (equal? (vector-ref descriptor 2)
                            (.ref clause 'variables))
                    (eq? (vector-ref descriptor 3)
                         (.ref clause 'variable)))
         (error "untrusted relational projection"))
       (relational-compute (vector-ref descriptor 3)
                            (vector-ref descriptor 1)
                            (vector-ref descriptor 2))))
    (else (error "unsupported relational clause"
                 (.ref clause 'ascent-clause-kind)))))

(def (relational-copy-rule rule)
  (gerbil-ascent-rule
   (map relational-copy-atom (.ref rule 'heads))
   (map relational-copy-clause (.ref rule 'body))))

;;; The engine constructor checks relation names, arities, rule bindings,
;;; dependencies and budgets before the admission value becomes observable.
(def (relational-snapshot-program program)
  (validate GerbilAscentProgramContract program)
  (gerbil-ascent-program
   (map (lambda (relation)
          (unless (eq? (.ref relation 'storage-kind) 'relation)
            (error "unsupported relational storage kind"))
          (relational-source
           (.ref relation 'name)
           (.ref relation 'arity)
           (map (lambda (row) (map identity row))
                (.ref relation 'rows))))
        (.ref program 'relations))
   (map relational-copy-rule (.ref program 'rules))
   (.ref program 'max-input-facts)
   (.ref program 'max-derived-facts)
   (.ref program 'max-output-facts)
   (.ref program 'source-handles)))

(def (relational-admit program)
  (let (snapshot (relational-snapshot-program program))
    (let ((run (gerbil-ascent-make-engine snapshot #f))
          (status 'ready)
          (complete-result #f))
      (make-relational-admission
       (lambda ()
         (case status
           ((complete) complete-result)
           ((failed) (error "relational solve previously failed"))
           ((running) (error "reentrant relational solve"))
           (else
            (set! status 'running)
            (with-catch
             (lambda (failure)
               (set! status 'failed)
               (raise failure))
             (lambda ()
               (let (result (run))
                 (unless (.ref result 'finished)
                   (error "relational solve did not complete"))
                 (set! complete-result result)
                 (set! status 'complete)
                 result))))))))))

;;; The prepared engine runs once. Successful repeats reuse its completed
;;; result; a failed run cannot expose or retry partially changed state.
(def (relational-solve admission)
  (unless (relational-admission? admission)
    (error "relational solve requires admission" admission))
  (make-relational-solution
   ((relational-admission-run admission))))

;;; Retained sessions accept replacements only through exported source
;;; handles. The old session owns rollback after an update or solve fails.
(def (relational-source-arities snapshot)
  (let (sources (.ref snapshot 'source-handles))
    (map (lambda (name)
           (let (relation
                 (find (lambda (candidate)
                         (eq? (.ref candidate 'name) name))
                       (.ref snapshot 'relations)))
             (unless relation
               (error "relational source has no declaration" name))
             (cons name (.ref relation 'arity))))
         sources)))

(def (relational-open-session program)
  (let* ((snapshot (relational-snapshot-program program))
         (arities (relational-source-arities snapshot)))
    (make-relational-session
     (gerbil-ascent-open-session snapshot)
     arities)))

(def (relational-open-program-session program)
  (let* ((snapshot (relational-snapshot-program program))
         (relations (.ref snapshot 'relations))
         (arities (relational-source-arities snapshot)))
    (unless (= (length relations) (length arities))
      (error "named program session requires source-capable relations"))
    (make-relational-program-session
     (gerbil-ascent-open-session snapshot)
     arities)))

(def (relational-replace-source/checked! engine arities name rows)
  (let (arity (and (symbol? name) (assq name arities)))
    (unless arity
      (error "relation is not a source in this session" name))
    (let (copied (map (lambda (row) (map identity row)) rows))
      (relational-source name (cdr arity) copied)
      (gerbil-ascent-session-replace-source! engine name copied)
      (void))))

(def (relational-session-replace-source! session fragment label rows)
  (unless (relational-session? session)
    (error "relational source replacement requires a session" session))
  (validate GerbilAscentFragmentContract fragment)
  (let* ((name (relational-export fragment label))
         (arity (assq name (relational-session-source-arities session))))
    (unless (and (memq name (.ref fragment 'source-handles)) arity)
      (error "relational export is not a source in this session" label))
    (relational-replace-source/checked!
     (relational-session-engine session)
     (relational-session-source-arities session) name rows)))

(def (relational-program-replace-source! session name rows)
  (unless (relational-program-session? session)
    (error "named source replacement requires a program session" session))
  (relational-replace-source/checked!
   (relational-program-session-engine session)
   (relational-program-session-source-arities session) name rows))

(def (relational-session-result engine)
  (let (result (gerbil-ascent-session-run engine))
    (unless (.ref result 'finished)
      (error "relational session did not complete"))
    result))

(def (relational-session-run session)
  (unless (relational-session? session)
    (error "relational run requires a session" session))
  (make-relational-solution
   (relational-session-result (relational-session-engine session))))

(def (relational-program-session-run session)
  (unless (relational-program-session? session)
    (error "named run requires a program session" session))
  (make-relational-program-solution
   (relational-session-result
    (relational-program-session-engine session))))
