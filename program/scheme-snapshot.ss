;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Rebuild caller declarations into the checked scalar grammar before planning.
;;; This owner constructs no evaluator or retained session.
(import "objects.ss" "scheme-checked.ss"
        (only-in "types.ss" GerbilAscentProgramContract)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate))
(export relational-snapshot-program)

;;; Admission rebuilds only the checked relational grammar. This removes
;;; caller-owned row/rule lists before planning and rejects old host callbacks.
(def (relational-copy-term term)
  (case (.ref term 'kind)
    ((variable) (gerbil-ascent-variable (.ref term 'value)))
    ((wildcard) (gerbil-ascent-wildcard))
    ((literal)
     (let (value (.ref term 'value))
       (unless (relational-scalar? value)
         (error "non-scalar relational literal" value))
       (gerbil-ascent-literal value)))
    (else (error "unsupported relational term" (.ref term 'kind)))))

;;; Rebuild from the descriptor, never from the callback stored for the old
;;; evaluator. An unmarked guard or binding cannot cross admission.
(def (relational-copy-clause clause)
  (case (.ref clause 'ascent-clause-kind)
    ((negation)
     (gerbil-ascent-negation
      (.ref clause 'relation)
      (map relational-copy-term (.ref clause 'terms))))
    ((aggregate)
     (let ((descriptor (.ref clause 'checked-operator))
           (terms (.ref clause 'terms)))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 6)
                    (eq? (vector-ref descriptor 0) 'reduce)
                    (eq? (vector-ref descriptor 2)
                         (.ref clause 'variable))
                    (eq? (vector-ref descriptor 3)
                         (.ref clause 'relation))
                    (equal? (vector-ref descriptor 4)
                            (.ref clause 'variables))
                    (equal? (vector-ref descriptor 5)
                            (relational-term-fingerprint terms))
                    (not (.ref clause 'output-pattern)))
         (error "untrusted relational reduction"))
       (relational-reducer
        (vector-ref descriptor 2) (vector-ref descriptor 1)
        (vector-ref descriptor 4) (vector-ref descriptor 3)
        (map relational-copy-term terms))))
    ((guard)
     (let (descriptor (.ref clause 'checked-operator))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 3)
                    (eq? (vector-ref descriptor 0) 'where)
                    (equal? (relational-operand-variables
                             (vector-ref descriptor 2))
                            (.ref clause 'variables)))
         (error "untrusted relational filter"))
       (relational-where (vector-ref descriptor 1)
                         (vector-ref descriptor 2))))
    ((binding)
     (let (descriptor (.ref clause 'checked-operator))
       (unless (and (vector? descriptor)
                    (= (vector-length descriptor) 4)
                    (eq? (vector-ref descriptor 0) 'compute)
                    (equal? (relational-operand-variables
                             (vector-ref descriptor 2))
                            (.ref clause 'variables))
                    (eq? (vector-ref descriptor 3)
                         (.ref clause 'variable)))
         (error "untrusted relational projection"))
       (relational-compute (vector-ref descriptor 3)
                            (vector-ref descriptor 1)
                            (vector-ref descriptor 2))))
    (else (error "unsupported relational clause"
                 (.ref clause 'ascent-clause-kind)))))

;;; Capture caller slots outside the private construction extent. Only closed
;;; canonical builders may execute inside it; no caller getter or supplied
;;; callback is retained. Nonatom descriptors keep their ordinary checked copy.
(def (relational-capture-term term)
  (case (.ref term 'kind)
    ((variable)
     (let (name (.ref term 'value))
       (unless (symbol? name) (error "ASCENT variable name must be a symbol" name))
       (lambda () (gerbil-ascent-variable name))))
    ((wildcard) (lambda () (gerbil-ascent-wildcard)))
    ((literal)
     (let (value (.ref term 'value))
       (unless (relational-scalar? value)
         (error "non-scalar relational literal" value))
       (lambda () (gerbil-ascent-literal value))))
    (else (error "unsupported relational term" (.ref term 'kind)))))

(def (relational-capture-atom atom)
  (unless (eq? (.ref atom 'ascent-clause-kind) 'atom)
    (error "unsupported relational clause"))
  (let ((name (.ref atom 'relation))
        (terms (map relational-capture-term (.ref atom 'terms))))
    (lambda () (gerbil-ascent-atom name (map (lambda (build) (build)) terms)))))

(def (relational-capture-clause clause)
  (if (eq? (.ref clause 'ascent-clause-kind) 'atom)
    (relational-capture-atom clause)
    (let (copied (relational-copy-clause clause)) (lambda () copied))))

(def (relational-capture-rule rule)
  (let ((heads (map relational-capture-atom (.ref rule 'heads)))
        (body (map relational-capture-clause (.ref rule 'body))))
    (lambda ()
      (gerbil-ascent-rule (map (lambda (build) (build)) heads)
                         (map (lambda (build) (build)) body)))))

;;; The engine constructor checks relation names, arities, rule bindings,
;;; dependencies and budgets before the admission value becomes observable.
(def (relational-snapshot-program program)
  (validate GerbilAscentProgramContract program)
  (let* ((relations
   (map (lambda (relation)
          (let* ((domain (.ref relation 'checked-domain))
                 (domains
                  (and domain
                       (begin
                         (unless (and (vector? domain) (= (vector-length domain) 2)
                                      (eq? (vector-ref domain 0) 'finite-domain))
                           (error "untrusted finite domain descriptor"))
                         (vector-ref domain 1))))
                 (name (.ref relation 'name)) (arity (.ref relation 'arity))
                 (rows (.ref relation 'rows)))
            (case (.ref relation 'storage-kind)
              ((relation)
               (if domain (relational-finite-source name arity rows domains)
                   (relational-source name arity rows)))
              ((lattice)
               (let (descriptor (.ref relation 'checked-operator))
                 (unless (and (vector? descriptor) (= (vector-length descriptor) 2)
                              (eq? (vector-ref descriptor 0) 'lattice))
                   (error "untrusted relational lattice"))
                 (if domain
                     (relational-finite-lattice name arity rows (vector-ref descriptor 1) domains)
                     (relational-checked-lattice name arity rows (vector-ref descriptor 1)))))
              (else (error "unsupported relational storage kind")))))
        (.ref program 'relations)))
         (rules (map relational-capture-rule (.ref program 'rules)))
         (input-limit (.ref program 'max-input-facts))
         (derived-limit (.ref program 'max-derived-facts))
         (output-limit (.ref program 'max-output-facts))
         (sources (.ref program 'source-handles)))
    ;; The source has already passed the ordinary complete Program contract.
    ;; This new, private tree passes that same complete contract after restoring
    ;; ordinary constructor checks. No Term validation result is memoized.
    (gerbil-ascent-construct-inert-program
     (lambda ()
       (gerbil-ascent-program relations (map (lambda (build) (build)) rules)
         input-limit derived-limit output-limit sources)) #f)))
