;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import "func.ss" "scheme-checked.ss" "scheme-session.ss"
        (only-in "scheme-query.ss" relational-program-query
                 relational-program-solution-with-provenance relational-program-solution-result)
        (only-in "result.ss" ordered-row-cut-delta)
        (only-in :gerbil-ascent/core/positive-plan current-retained-positive-plan-cost
                 make-positive-plan-cost positive-plan-cost-snapshot
                 current-static-prefix-cache make-bounded-static-prefix-cache)
        :gerbil-ascent/core/execution-control
        (only-in :clan/poo/object .ref)
        (only-in :std/list/list split-at take drop delete-duplicates/hash list-sort)
        (only-in :std/struct/rbtree RBTree rbtree-copy rbtree-get rbtree-put!
                 rbtree-remove! rbtree-empty? rbtree-for-each rbtree->list)
        (only-in :std/error deferror-class))

(export make-relational-choice-head lower-relational-choice-program
        relational-choice-solve RelationalChoiceLimit?
        call-with-relational-choice-measurement)

(defstruct relational-choice-head (kind relation keys values body origin))
(defstruct relational-choice-offer (relation kind attribute bindings width ordinal rule premises))
;; Frozen buckets. Tree headers fork in constant time and each write replaces
;; a bucket, so a saved parent never observes a child's edits.
(defstruct choice-constraint (rank first-closed closed open closed-support) final: #t)
(defstruct choice-entry (state parent addition trace) final: #t)
(defstruct choice-step (assignment kind support) final: #t)
(defstruct choice-parent (cut constraints units remaining) final: #t)
(defstruct relational-choice-program (grounding offers choice-names))
(deferror-class RelationalChoiceLimit ())

(defstruct choice-measurement
  (mode start first-model states new-offers repeat-offers rebuilds extensions
   source-replacements parent-restores parent-captures peak-parent-units) final: #t)
(def current-choice-measurement (make-parameter #f))
(def (elapsed-ns start)
  (quotient (* (- (current-jiffy) start) 1000000000) (jiffies-per-second)))

;; Benchmark one native invocation without changing its publication boundary.
(def (call-with-relational-choice-measurement run (mode #f))
  (let* ((prefix (make-positive-plan-cost #f))
         (meter (make-choice-measurement mode (current-jiffy) #f 0 0 0 0 0 0 0 0 0))
         (models (parameterize ((current-choice-measurement meter)
                                (current-retained-positive-plan-cost prefix))
                   (run)))
         (duration (elapsed-ns (choice-measurement-start meter))))
    (using (meter :- choice-measurement)
      (values models
        (let (work (positive-plan-cost-snapshot prefix))
          (list (assq 'partial-matches work) (assq 'prefix-state-replays work)
              (cons 'new-offers meter.new-offers) (cons 'repeated-offers meter.repeat-offers)
              (cons 'states meter.states) (cons 'rebuilds meter.rebuilds)
              (cons 'extensions meter.extensions)
              (cons 'source-replacements meter.source-replacements)
              (cons 'parent-restores meter.parent-restores)
              (cons 'parent-captures meter.parent-captures)
              (cons 'peak-parent-units meter.peak-parent-units)
              (cons 'first-model-ns meter.first-model) (cons 'total-ns duration)))))))

(def (rank<? left right)
  (or (< (car left) (car right))
      (and (= (car left) (car right)) (< (cdr left) (cdr right)))))

;; Compile each choice rule to a private positive relation containing the
;; grounded attribute arguments followed by its offered values.
(def (lower-relational-choice-program base choice-names heads)
  (let* ((relations (.ref base 'relations))
         (arities (map (lambda (relation)
                         (cons (.ref relation 'name) (.ref relation 'arity)))
                       relations))
         (offers (map (lambda (head) (gensym 'choice-offer)) heads)))
    (def ordinal 0)
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
              (hash-put! seen variable (hash-length seen))
              (set! bindings (cons term bindings)))
            term))
        (let* ((body
                (map (lambda (atom)
                       (gerbil-ascent-atom (.ref atom 'relation)
                         (map capture-term (.ref atom 'terms))))
                     (relational-choice-head-body head)))
               (terms (append (reverse! bindings) keys values))
               (rule (relational-rule/reader-origin
                      (list (gerbil-ascent-atom offer terms)) body
                      (relational-choice-head-origin head)))
               (premises
                (map (lambda (atom)
                       (cons (.ref atom 'relation)
                         (map (lambda (term)
                                (let (value (.ref term 'value))
                                  (if (eq? (.ref term 'kind) 'variable)
                                    (hash-ref seen value)
                                    (list value))))
                              (.ref atom 'terms)))) body))
               (compiled (make-relational-choice-offer offer (relational-choice-head-kind head)
                           name (hash-length seen) (length keys) ordinal rule premises)))
          (set! ordinal (+ ordinal 1))
          (list (relational-with-role (relational-source offer (length terms) []) 'derived)
                rule compiled))))
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

;; A completed solution retains one derivation in deduction order. The
;; grounded supports are owned rows from the predecessor cut of each step.
(def (explain-choice trace names name)
  (unless (memq name names) (error "choice provenance requires a choice relation" name))
  (filter-map
   (lambda ((step :- choice-step))
     (ascent-execution-checkpoint! 1 0)
     (and (eq? name (car step.assignment))
          (list step.kind (append step.assignment [])
            (map (lambda (support)
                   (ascent-execution-checkpoint! 1 0)
                   (let ((offer (car support)) (row (cdr support)))
                     (using (offer :- relational-choice-offer)
                       (let (bindings (list->vector (take row offer.bindings)))
                         (list offer.ordinal offer.kind
                               (relational-rule-origin offer.rule)
                               (map (lambda (premise)
                                      (ascent-execution-checkpoint! 1 0)
                                      (cons (car premise)
                                        (map (lambda (term)
                                               (if (pair? term) (car term)
                                                 (vector-ref bindings term)))
                                             (cdr premise)))) offer.premises)
                               (append (drop row (+ offer.bindings offer.width)) []))))))
                 step.support))))
   (reverse trace)))

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
  (def (enqueue! state parent addition trace (kind #f) (support []))
    (checkpoint!)
    (unless (hash-get seen state)
      (when (>= (hash-length seen) budget)
        (raise (RelationalChoiceLimit "finite-choice state budget exhausted" irritants: (list budget))))
      (hash-put! seen state #t)
      (set! pending
        (cons (make-choice-entry state parent addition
                (if kind (cons (make-choice-step (source-row addition) kind support) trace) trace))
              pending))
      #t))
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
  ;; BEGIN GENERATED CHOICE BRANCH
  (defrule (install-choice-cut current? child? current-expr append-expr replace-expr)
    (if current? current-expr
      (if child? append-expr replace-expr)))
  ;; END GENERATED CHOICE BRANCH
  (def (install-state! session state parent addition)
    (install-choice-cut (eq? state current) (eq? parent current)
      (relational-program-session-run session)
      (let (row (source-row addition))
        (relational-program-append-source! session (car row) (cdr row))
        (relational-program-session-run session))
      (let (rows (make-hash-table-eq))
        (for-each (lambda (assignment)
                    (checkpoint!)
                    (let (row (source-row assignment))
                      (hash-put! rows (car row)
                        (cons (cdr row) (hash-ref rows (car row) [])))))
                  state)
        (relational-program-transaction! session
          (map (lambda (name) (cons name (reverse! (hash-ref rows name [])))) names)))))
  (def constraints #f)
  (def offer-roots #f)
  (def offer-sizes #f)
  (def read-root #f)
  (def save-parent #f)
  (def restore-parent! #f)
  (def saved (make-hash-table-eq))
  (def parent-units 0)
  (def offers (relational-choice-program-offers program))
  (def meter (current-choice-measurement))
  (def mode (and meter (choice-measurement-mode meter)))
  (def rescan? (eq? mode #t))
  (def (read-offer-roots completed)
    (map (lambda (offer) (read-root completed (relational-choice-offer-relation offer))) offers))
  (def (remember-parent! state result children)
    (when (and (not mode) (> children 1) offer-roots (andmap identity offer-roots))
      ;; Charge even the shared static rows. The existing state budget also
      ;; bounds total retained logical rows and relation headers here.
      (let* ((sizes ((.ref (relational-program-solution-result result) 'relation-sizes)))
             (units (foldl (lambda (entry total) (+ total 1 (cdr entry))) 0 sizes)))
        (when (<= (+ parent-units units) budget)
          (let (cut (save-parent state))
            (when cut
              (set! parent-units (+ parent-units units))
              (hash-put! saved state (make-choice-parent cut (rbtree-copy constraints) units children))
              (when meter
                (using (meter :- choice-measurement)
                  (set! meter.parent-captures (+ 1 meter.parent-captures))
                  (set! meter.peak-parent-units (max parent-units meter.peak-parent-units))))))))))
  (def (take-parent! parent)
    (alet (candidate (hash-get saved parent))
      (using (candidate :- choice-parent)
        (set! candidate.remaining (- candidate.remaining 1))
        (when (zero? candidate.remaining)
          (set! parent-units (- parent-units candidate.units))
          (hash-remove! saved parent)))
      candidate))
  (def (process! state result trace addition)
    (let/cc finish
      (def children 0)
      (def (reject!)
        (set! offer-roots #f)
        (set! constraints #f)
        (finish (void)))
      (def (intersect left right)
        (filter (lambda (value) (checkpoint!) (member value right)) left))
      (def (register! id open? values support)
        (let* ((rank (car support))
               (prior (rbtree-get constraints id))
               (earliest (and prior (choice-constraint-rank prior)))
               (order (if (and earliest (rank<? earliest rank)) earliest rank))
               (first (and prior (choice-constraint-first-closed prior)))
               (closed (and prior (choice-constraint-closed prior)))
               (open (if prior (choice-constraint-open prior) []))
               (supports (if prior (choice-constraint-closed-support prior) [])))
          (rbtree-put! constraints id
            (if open?
              (make-choice-constraint order first closed (cons support open) supports)
              (let* ((earlier? (or (not first) (rank<? rank first)))
                     (allowed
                      (cond ((not closed) (delete-duplicates/hash values))
                            (earlier? (intersect (delete-duplicates/hash values) closed))
                            (else (intersect closed values)))))
                (when (null? allowed) (reject!))
                (make-choice-constraint order (if earlier? rank first) allowed open
                  (cons support supports)))))))
      (def (support-order supports)
        (list-sort (lambda (a b) (rank<? (car b) (car a))) supports))
      (def (schedule! id value kind supports)
        (checkpoint!)
        (let (assignment (cons id value))
          (when (enqueue! (insert-choice state id value) state assignment trace kind supports)
            (set! children (+ children 1)))))
      (let* ((completed (relational-program-solution-result result))
             (roots (and (not rescan?) (read-offer-roots completed)))
             (candidate (and addition offer-roots roots
                             (map (lambda (now before)
                                    (and now before (ordered-row-cut-delta now before))) roots offer-roots)))
             (updates (and candidate (andmap identity candidate) (list->vector candidate))))
        (when meter
          (using (meter :- choice-measurement)
            (set! meter.states (+ meter.states 1))
            (if updates (set! meter.extensions (+ meter.extensions 1))
              (set! meter.rebuilds (+ meter.rebuilds 1)))))
        (if updates
          (let* ((id (car addition)) (cached (rbtree-get constraints id)))
            (checkpoint!)
            (when cached
              (let (closed (choice-constraint-closed cached))
                (when (and closed (not (member (cdr addition) closed))) (reject!)))
              (rbtree-remove! constraints id)))
          (set! constraints (RBTree -)))
        (set! offer-roots roots)
        (let (sizes (and meter (make-vector (length offers) 0)))
          (for-each
           (lambda (offer)
             (checkpoint!)
             (using (offer :- relational-choice-offer)
               (let* ((update (and updates (vector-ref updates offer.ordinal)))
                      (start (if update (car update) 0))
                      (rows (if update (cdr update) (relational-program-query result offer.relation))))
                 (when meter
                   (using (meter :- choice-measurement)
                     (let* ((read (length rows)) (size (+ start read))
                            (repeat (if (and (not update) addition offer-sizes)
                                      (min read (vector-ref offer-sizes offer.ordinal)) 0)))
                       (vector-set! sizes offer.ordinal size)
                       (set! meter.new-offers (+ meter.new-offers (- read repeat)))
                       (set! meter.repeat-offers (+ meter.repeat-offers repeat)))))
                 (let scan ((rows rows) (position start))
                   (unless (null? rows)
                     (checkpoint!)
                     (let (row (car rows))
                       (let-values (((args values) (split-at (drop row offer.bindings) offer.width)))
                         (let* ((id (attribute-id offer.attribute args))
                                (prior (assv id state))
                                (open? (eq? offer.kind 'open)))
                           (if prior
                             (unless (or open? (member (cdr prior) values)) (reject!))
                             (register! id open? values (cons (cons offer.ordinal position) (cons offer row)))))))
                     (scan (cdr rows) (+ position 1)))))))
           offers)
          (set! offer-sizes sizes)))
      (if (rbtree-empty? constraints)
        (begin
          (when (and meter (not (choice-measurement-first-model meter)))
            (choice-measurement-first-model-set! meter (elapsed-ns (choice-measurement-start meter))))
          (set! models (cons (relational-program-solution-with-provenance result
                               (cut explain-choice trace names <>)) models)))
        (let ((forced #f) (closed-key #f))
          (def (later? prior constraint)
            (or (not prior)
                (rank<? (choice-constraint-rank (cdr prior)) (choice-constraint-rank constraint))))
          ;; The first forced or closed key in reverse publication order
          ;; can be selected in one pass. Sort only when visiting every open key.
          (rbtree-for-each
           (lambda (id (constraint :- choice-constraint))
             (when constraint.closed
               (when (later? closed-key constraint) (set! closed-key (cons id constraint)))
               (when (and (null? (cdr constraint.closed)) (later? forced constraint))
                 (set! forced (cons id constraint)))))
           constraints)
          (if (or forced closed-key)
            (let* ((entry (or forced closed-key)) (id (car entry)) (constraint (cdr entry)))
              (using (constraint :- choice-constraint)
                (let (supports (map cdr (support-order constraint.closed-support)))
                  (for-each (lambda (value)
                              (schedule! id value (if forced 'deduction 'branch) supports))
                            constraint.closed))))
            ;; With only open offers, another key can enable a new value.
            (for-each
             (lambda (entry)
               (for-each
                (lambda (ranked)
                  (let* ((support (cdr ranked)) (offer (car support)) (row (cdr support)))
                    (using (offer :- relational-choice-offer)
                      (schedule! (car entry) (list-ref row (+ offer.bindings offer.width)) 'branch (list support)))))
                (support-order (choice-constraint-open (cdr entry)))))
             (list-sort (lambda (a b)
                          (rank<? (choice-constraint-rank (cdr b)) (choice-constraint-rank (cdr a))))
                        (rbtree->list constraints))))))
      (remember-parent! state result children)))
  ;; Intermediate Session commits are private. Keep cancellation and all
  ;; work charges active, but linearize only the final public model list.
  (enqueue! [] #f #f [])
  (parameterize
    ((current-ascent-execution-control
      (and control (lambda (work facts) (control (if (= work -1) 0 work) facts))))
     (current-static-prefix-cache (and (not mode) (make-bounded-static-prefix-cache names budget))))
    (let (session (relational-open-program-session/choice (relational-choice-program-grounding program)
                     (lambda (reader capture restore)
                       (set! read-root reader)
                       (set! save-parent capture)
                       (set! restore-parent! restore))))
      (let search ()
        (unless (null? pending)
          (checkpoint!)
          (let (entry (car pending))
            (set! pending (cdr pending))
            (using (entry :- choice-entry)
              (let (parent (take-parent! entry.parent))
                (when (and parent (not (eq? entry.parent current)))
                  (let (completed (restore-parent! (choice-parent-cut parent) entry.parent))
                    (set! constraints (rbtree-copy (choice-parent-constraints parent)))
                    (set! offer-roots (read-offer-roots completed))
                    (set! current entry.parent)
                    (when meter
                      (choice-measurement-parent-restores-set! meter
                        (+ 1 (choice-measurement-parent-restores meter)))))))
              (let (addition (and (eq? entry.parent current) entry.addition))
                (unless addition
                  ;; Release the discarded branch before materializing its sibling.
                  (set! offer-roots #f)
                  (set! constraints #f)
                  (when (and meter (not (eq? entry.state current)))
                    (choice-measurement-source-replacements-set! meter
                      (+ 1 (choice-measurement-source-replacements meter)))))
                (let (result (install-state! session entry.state entry.parent entry.addition))
                  (set! current entry.state)
                  (process! entry.state result entry.trace addition))))
            (search))))))
  (let (result (reverse! models))
    (ascent-accept-publication!)
    result))
