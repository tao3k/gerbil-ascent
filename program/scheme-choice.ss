;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import "func.ss" "scheme-checked.ss" "scheme-session.ss"
        (only-in "scheme-query.ss" relational-program-query)
        :gerbil-ascent/core/execution-control
        (only-in :clan/poo/object .ref)
        (only-in :std/list/list split-at drop delete-duplicates/hash)
        (only-in :std/error deferror-class))

(export make-relational-choice-head lower-relational-choice-program
        relational-choice-solve RelationalChoiceLimit?)

(defstruct relational-choice-head (kind relation keys values body origin))
(defstruct relational-choice-offer (relation kind attribute bindings width))
(defstruct choice-constraint (closed open) final: #t)
(defstruct relational-choice-program (grounding offers choice-names))
(deferror-class RelationalChoiceLimit ())

;; Compile each choice rule to a private positive relation containing the
;; grounded attribute arguments followed by its offered values.
(def (lower-relational-choice-program base choice-names heads)
  (let* ((relations (.ref base 'relations))
         (arities (map (lambda (relation)
                         (cons (.ref relation 'name) (.ref relation 'arity)))
                       relations))
         (offers (map (lambda (head) (gensym 'choice-offer)) heads)))
    ;; Name each wildcard occurrence to retain the matching row identity.
    ;; All other variables retain their existing binding and equality checks.
    (def (compile-head head offer)
      (let* ((name (relational-choice-head-relation head))
             (keys (relational-choice-head-keys head))
             (values (relational-choice-head-values head))
             (arity (assq name arities))
             (seen (make-hash-table-eq))
             (bindings []))
        (unless (and (memq name choice-names) arity (= (cdr arity) (+ 1 (length keys))))
          (error "invalid relational choice attribute" name))
        (def (capture-term term)
          (let* ((term (if (eq? (.ref term 'kind) 'wildcard)
                         (gerbil-ascent-variable (gensym 'choice-witness)) term))
                 (variable (and (eq? (.ref term 'kind) 'variable) (.ref term 'value))))
            (when (and variable (not (hash-get seen variable)))
              (hash-put! seen variable #t)
              (set! bindings (cons term bindings)))
            term))
        (let* ((body
                (map (lambda (atom)
                       (gerbil-ascent-atom (.ref atom 'relation)
                         (map capture-term (.ref atom 'terms))))
                     (relational-choice-head-body head)))
               (terms (append (reverse! bindings) keys values)))
          (list
           (relational-with-role (relational-source offer (length terms) []) 'derived)
           (relational-rule/reader-origin
            (list (gerbil-ascent-atom offer terms)) body
            (relational-choice-head-origin head))
           (make-relational-choice-offer offer (relational-choice-head-kind head)
             name (hash-length seen) (length keys))))))
    ;; Monotone positive bodies are the premise for factoring deterministic
    ;; closure through Session. Choice predicates have a single writer.
    (for-each
     (lambda (rule)
       (unless (and (andmap (lambda (clause) (eq? (.ref clause 'ascent-clause-kind) 'atom))
                            (.ref rule 'body))
                    (not (ormap (lambda (head) (memq (.ref head 'relation) choice-names))
                                (.ref rule 'heads))))
         (error "choice programs require positive rules and explicit choice writers")))
     (.ref base 'rules))
    (let (compiled (map compile-head heads offers))
      (make-relational-choice-program
       (gerbil-ascent-program
        (append relations (map car compiled))
        (append (.ref base 'rules) (map cadr compiled))
        (.ref base 'max-input-facts) (.ref base 'max-derived-facts) (.ref base 'max-output-facts)
        (.ref base 'source-handles))
       (map caddr compiled) choice-names))))

;; Canonical numeric attribute identities make state equality independent
;; of the path used to derive it. Existing entries are immutable.
(def (insert-choice state id value)
  (if (or (null? state) (< id (caar state)))
    (cons (cons id value) state)
    (cons (car state) (insert-choice (cdr state) id value))))

;; Each invocation owns its Session and worklist. A direct child appends one
;; assignment; crossing to another branch installs an atomic source cut.
(def (relational-choice-solve program state-budget: budget)
  (unless (and (relational-choice-program? program)
               (exact-integer? budget) (>= budget 0))
    (error "invalid relational choice solve inputs"))
  (def control (current-ascent-execution-control))
  (def (checkpoint!) (ascent-execution-checkpoint! 1 0))
  (def seen (make-hash-table))
  (def attributes (make-hash-table))
  (def keys (make-hash-table-eqv))
  (def names (relational-choice-program-choice-names program))
  (def pending [])
  (def models [])
  (def current [])
  (def (enqueue! state parent addition)
    (checkpoint!)
    (unless (hash-get seen state)
      (when (>= (hash-length seen) budget)
        (raise (RelationalChoiceLimit "finite-choice state budget exhausted" irritants: (list budget))))
      (hash-put! seen state #t)
      (set! pending (cons (vector state parent addition) pending))))
  (def (attribute-id name args)
    (let (key (cons name args))
      (or (hash-get attributes key)
          (let (id (hash-length attributes))
            (hash-put! attributes key id)
            (hash-put! keys id key)
            id))))
  (def (source-row assignment)
    (let (key (hash-ref keys (car assignment)))
      (cons (car key) (append (cdr key) (list (cdr assignment))))))
  (def (install-state! session state parent addition)
    (cond
      ((eq? state current) (relational-program-session-run session))
      ((eq? parent current)
       (let (row (source-row addition))
         (relational-program-append-source! session (car row) (cdr row))
         (relational-program-session-run session)))
      (else
       (let (rows (make-hash-table-eq))
         (for-each (lambda (assignment)
                     (checkpoint!)
                     (let (row (source-row assignment))
                       (hash-put! rows (car row)
                         (cons (cdr row) (hash-ref rows (car row) [])))))
                   state)
         (relational-program-transaction! session
           (map (lambda (name) (cons name (reverse! (hash-ref rows name [])))) names))))))
  (def (process! state result)
    (let/cc reject
      (let ((constraints (make-hash-table-eqv)) (order []) (forced #f))
        (def (register! id open? values)
          (let (constraint
                (or (hash-get constraints id)
                    (let (fresh (make-choice-constraint #f []))
                      (hash-put! constraints id fresh)
                      (set! order (cons id order))
                      fresh)))
            (using (constraint :- choice-constraint)
              (if open?
                (set! constraint.open (cons (car values) constraint.open))
                (let (allowed
                      (if constraint.closed
                        (filter (lambda (value)
                                  (checkpoint!)
                                  (member value values))
                                constraint.closed)
                        (delete-duplicates/hash values)))
                  (when (null? allowed) (reject (void)))
                  (set! constraint.closed allowed))))))
        (for-each
         (lambda (offer)
           (checkpoint!)
           (using (offer :- relational-choice-offer)
             (for-each
              (lambda (row)
                (checkpoint!)
                (let-values (((args values) (split-at (drop row offer.bindings) offer.width)))
                  (let* ((id (attribute-id offer.attribute args))
                         (prior (assv id state))
                         (open? (eq? offer.kind 'open)))
                    (if prior
                      (unless (or open? (member (cdr prior) values)) (reject (void)))
                      (register! id open? values)))))
              (relational-program-query result offer.relation))))
         (relational-choice-program-offers program))
        (def (schedule! id value)
          (checkpoint!)
          (enqueue! (insert-choice state id value) state (cons id value)))
        (if (null? order)
          (set! models (cons result models))
          (begin
            (for-each
             (lambda (id)
               (let (constraint (hash-ref constraints id))
                 (using (constraint :- choice-constraint)
                   (when (and (not forced) (pair? constraint.closed) (null? (cdr constraint.closed)))
                     (set! forced (cons id (car constraint.closed)))))))
             order)
            ;; Only a singleton closed intersection can suppress other
            ;; scheduling. An open offer may be superseded by a value whose
            ;; supporting rule has yet to become enabled.
            (if forced
              (schedule! (car forced) (cdr forced))
              (for-each
               (lambda (id)
                 (let (constraint (hash-ref constraints id))
                   (for-each (cut schedule! id <>)
                     (or (choice-constraint-closed constraint)
                         (choice-constraint-open constraint)))))
               order)))))))
  ;; Intermediate Session commits are private. Keep cancellation and all
  ;; work charges active, but linearize only the final public model list.
  (enqueue! [] #f #f)
  (parameterize
    ((current-ascent-execution-control
      (and control (lambda (work facts) (control (if (= work -1) 0 work) facts)))))
    (let (session (relational-open-program-session (relational-choice-program-grounding program)))
      (let search ()
        (unless (null? pending)
          (checkpoint!)
          (let* ((entry (car pending))
                 (state (vector-ref entry 0)))
            (set! pending (cdr pending))
            (let (result (install-state! session state (vector-ref entry 1) (vector-ref entry 2)))
              (set! current state)
              (process! state result))
            (search))))))
  (let (result (reverse! models))
    (ascent-accept-publication!)
    result))
