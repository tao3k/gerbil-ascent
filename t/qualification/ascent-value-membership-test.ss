;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .cc .ref .putslot! object-instance $constant-slot-spec $thunk-slot-spec)
        (only-in :clan/poo/mop element? validate)
        (only-in :yuanxu/types yuanxu-contract-admit yuanxu-validation-evidence-accepted?
                 yuanxu-classification-evidence)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider GerbilAscentIndexProviderContract)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-variable gerbil-ascent-atom gerbil-ascent-relation gerbil-ascent-rule gerbil-ascent-program gerbil-ascent-guard
                 gerbil-ascent-construct-inert-program)
        (only-in :gerbil-ascent/program/types GerbilAscentTermContract GerbilAscentAtomContract GerbilAscentRuleContract GerbilAscentGuardContract
                 GerbilAscentSessionContract gerbil-ascent-make-session-value
                 GerbilAscentRelationContract GerbilAscentProgramContract gerbil-ascent-make-relation-value gerbil-ascent-make-rule-value gerbil-ascent-make-atom-value))
(export ascent-value-membership-test)

(def (nested-term? term)
  (element? (.ref (.ref GerbilAscentAtomContract 'responsibilities) 'terms) (list term)))

(def (observe-term construct predicate)
  (let (trace [])
    (def (emit name value) (set! trace (cons name trace)) value)
    (let* ((term (construct emit))
           (answer (with-catch (lambda (failure) (list 'raised failure))
                     (lambda () (if (predicate term) #t #f)))))
      (list answer (reverse trace)))))

(def (compare-term construct)
  (check-equal? (observe-term construct nested-term?)
                (observe-term construct (cut element? GerbilAscentTermContract <>))))

(def (nested-relation? relation)
  (element? (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'relations) (list relation)))
(def (plain-relation provider)
  (.o (:: @ (.ref GerbilAscentRelationContract 'proto))
      name: 'input arity: 1 rows: '((a)) field-predicates: [] storage-kind: 'relation
      index-provider: provider storage-provider: gerbil-ascent-set-storage-provider))

(def ascent-value-membership-test
  (test-suite "Nested value membership preserves public admission"
    (test-case "owned public Term Atom and Rule constructors honor validation and normalization hooks"
      (let* ((term (gerbil-ascent-variable 'x)) (atom (gerbil-ascent-atom 'r (list term))))
        (for-each (lambda (root construct)
          (let ((validator (.ref root '.validate)) (calls 0))
            (try
              (hash-put! (object-instance root) '.validate
                (lambda (candidate) (set! calls (+ calls 1)) (validator candidate)))
              (let (value (construct))
                (check-equal? calls 1)
                (check-equal? (eq? (validate root value) value) #t)
                (check-equal? calls 2))
              (hash-put! (object-instance root) '.validate (lambda (_) 'normalized-declaration))
              (check-equal? (construct) 'normalized-declaration)
              (finally (hash-put! (object-instance root) '.validate validator)))))
          (list GerbilAscentTermContract GerbilAscentAtomContract GerbilAscentRuleContract)
          (list (lambda () (gerbil-ascent-variable 'x))
                (lambda () (gerbil-ascent-atom 'r (list term)))
                (lambda () (gerbil-ascent-rule (list atom) (list atom)))))))
    (test-case "positive Rule constructors and nested membership retain opaque clause admission"
      (let* ((atom (gerbil-ascent-atom 'r (list (gerbil-ascent-variable 'x))))
             (guard (gerbil-ascent-guard [] (lambda () #t)))
             (value (gerbil-ascent-make-rule-value (.ref GerbilAscentRuleContract 'proto)
                       (list atom) (list guard)))
             (admit (.ref GerbilAscentGuardContract '.admit)) (calls 0))
        (try
          (hash-put! (object-instance GerbilAscentGuardContract) '.admit
            (lambda args (set! calls (+ calls 1)) (raise 'opaque-clause-admission)))
          (check-equal? (with-catch (lambda (failure) failure)
            (lambda () (gerbil-ascent-rule (list atom) (list guard)))) 'opaque-clause-admission)
          (check-equal? calls 1)
          (set! calls 0)
          (check-equal? (with-catch (lambda (failure) failure)
            (lambda () (element? (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'rules) (list value))))
            'opaque-clause-admission)
          (check-equal? calls 1)
          (finally (hash-put! (object-instance GerbilAscentGuardContract) '.admit admit)))))
    (test-case "a failed positive Rule view still enters alternative public clause contracts"
      (let* ((term (gerbil-ascent-variable 'x))
             (atom (gerbil-ascent-atom 'r (list term)))
             (bad (gerbil-ascent-make-atom-value (.ref GerbilAscentAtomContract 'proto)
                    99 (list term) (lambda args #f)))
             (value (gerbil-ascent-make-rule-value (.ref GerbilAscentRuleContract 'proto)
                      (list atom) (list bad)))
             (admit (.ref GerbilAscentGuardContract '.admit)) (calls 0))
        (try
          (hash-put! (object-instance GerbilAscentGuardContract) '.admit
            (lambda args (set! calls (+ calls 1)) (raise 'alternative-clause-admission)))
          (check-equal? (with-catch (lambda (failure) failure)
            (lambda () (element? (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'rules) (list value))))
            'alternative-clause-admission)
          (check-equal? calls 1)
          (set! calls 0)
          (check-equal? (with-catch (lambda (failure) failure)
            (lambda () (gerbil-ascent-rule (list atom) (list bad)))) 'alternative-clause-admission)
          (check-equal? calls 1)
          (finally (hash-put! (object-instance GerbilAscentGuardContract) '.admit admit)))))
    (test-case "positive Rule checks preserve late root obligations from head admission"
      (let* ((root GerbilAscentRuleContract)
             (atom (gerbil-ascent-atom 'r (list (gerbil-ascent-variable 'x))))
             (value (gerbil-ascent-make-rule-value (.ref root 'proto) (list atom) (list atom)))
             (heads (.ref (.ref root 'responsibilities) 'heads))
             (admit (.ref heads '.admit)) (obligations (.ref root '.obligations)) (seen []))
        (def (observe thunk)
          (set! seen [])
          (hash-put! (object-instance root) '.obligations obligations)
          (let (answer (with-catch (lambda (failure) failure) thunk)) (list answer (reverse seen))))
        (try
          (hash-put! (object-instance heads) '.admit
            (lambda (candidate context)
              (set! seen (cons 'heads-admit seen))
              (let (evidence (admit candidate context))
                (hash-put! (object-instance root) '.obligations
                  (lambda args (set! seen (cons 'rule-obligation seen)) (raise 'late-rule-obligation)))
                evidence)))
          (check-equal? (observe (lambda () (gerbil-ascent-rule (list atom) (list atom))))
                        '(late-rule-obligation (heads-admit rule-obligation)))
          (check-equal? (observe (lambda () (element? (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'rules) (list value))))
                        (observe (lambda () (element? root value))))
          (finally
            (hash-put! (object-instance heads) '.admit admit)
            (hash-put! (object-instance root) '.obligations obligations)))))
    (test-case "Atom construction preserves unowned Term getter traces and exceptions"
      (for-each (lambda (raise?)
        (def (construct emit)
          (.o (:: @ (.ref GerbilAscentTermContract 'proto))
              (kind (emit 'kind 'variable))
              (value (if raise? (begin (emit 'value #f) (raise 'term-value)) (emit 'value 'x)))))
        (check-equal?
          (observe-term construct (lambda (term) (gerbil-ascent-atom 'r (list term))))
          (observe-term construct (lambda (term)
            (validate GerbilAscentAtomContract
              (.o (:: @ (.ref GerbilAscentAtomContract 'proto))
                  ascent-clause-kind: 'atom relation: 'r terms: (list term) .plan: (lambda args #f)))))))
        '(#f #t)))
    (test-case "Atom construction observes a late parent obligation from child admission"
      (let* ((term (gerbil-ascent-variable 'x)) (admit (.ref GerbilAscentTermContract '.admit))
             (obligations (.ref GerbilAscentAtomContract '.obligations)) (seen []))
        (def (observe construct)
          (set! seen [])
          (hash-put! (object-instance GerbilAscentAtomContract) '.obligations obligations)
          (let (answer (with-catch (lambda (failure) failure) construct))
            (list answer (reverse seen))))
        (try
          (hash-put! (object-instance GerbilAscentTermContract) '.admit
            (lambda (candidate context)
              (set! seen (cons 'term-admit seen))
              (let (evidence (admit candidate context))
                (hash-put! (object-instance GerbilAscentAtomContract) '.obligations
                  (lambda args (set! seen (cons 'atom-obligation seen)) (raise 'late-construction-obligation)))
                evidence)))
          (check-equal?
            (observe (lambda () (gerbil-ascent-atom 'r (list term))))
            (observe (lambda ()
              (validate GerbilAscentAtomContract
                (.o (:: @ (.ref GerbilAscentAtomContract 'proto))
                    ascent-clause-kind: 'atom relation: 'r terms: (list term) .plan: (lambda args #f))))))
          (finally
            (hash-put! (object-instance GerbilAscentTermContract) '.admit admit)
            (hash-put! (object-instance GerbilAscentAtomContract) '.obligations obligations)))))
    (test-case "owned Session publication preserves all five operations and contextual obligations"
      (let* ((operation (lambda args 'called))
             (session (gerbil-ascent-make-session-value operation operation operation operation operation))
             (seen [])
             (context (.o (.contract-obligations
                       (lambda (contract _candidate)
                         (set! seen (cons (.ref contract 'identity) seen)) [])))))
        (for-each (lambda (slot) (check-equal? (.ref session slot) operation))
          '(.append-source! .replace-source! .replace-sources! .run .run-timeout))
        (check-equal? (element? GerbilAscentSessionContract session) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit GerbilAscentSessionContract session context)) #t)
        (check-equal? (length seen) 4)
        (check-equal? (car seen) 'ascent/session)))
    (test-case "invalid mandatory Session operations still raise during publication"
      (let (operation (lambda args (void)))
        (for-each (lambda (position)
          (let (operations (list operation operation operation operation operation))
            (set-car! (list-tail operations position) #f)
            (check-equal? (with-catch (lambda (_failure) 'raised)
                            (lambda () (apply gerbil-ascent-make-session-value operations) 'accepted))
                          'raised))) '(0 1 3))))
    (test-case "Session publication honors live validation dispatch and normalization"
      (let* ((validator (.ref GerbilAscentSessionContract '.validate))
             (operation (lambda args (void)))
             (sentinel (.o)) (calls 0))
        (try
          (hash-put! (object-instance GerbilAscentSessionContract) '.validate
            (lambda args (set! calls (+ calls 1)) sentinel))
          (check-equal? (gerbil-ascent-make-session-value operation operation operation operation operation)
                        sentinel)
          (check-equal? calls 1)
          (finally (hash-put! (object-instance GerbilAscentSessionContract) '.validate validator)))))
    (test-case "Session publication honors root and field admission and obligation dispatch"
      (let* ((operation (lambda args (void)))
             (field (.ref (.ref GerbilAscentSessionContract 'responsibilities) '.run)))
        (for-each (lambda (descriptor)
          (for-each (lambda (slot)
            (let ((original (.ref descriptor slot)) (calls 0))
              (try
                (hash-put! (object-instance descriptor) slot
                  (lambda args (set! calls (+ calls 1)) (apply original args)))
                (let (session (gerbil-ascent-make-session-value
                                operation operation operation operation operation))
                  (check-equal? (> calls 0) #t)
                  (check-equal? (element? GerbilAscentSessionContract session) #t))
                (finally (hash-put! (object-instance descriptor) slot original)))))
            '(.admit .obligations))) (list GerbilAscentSessionContract field))))
    (test-case "Session publication honors live field classifier rejection"
      (let* ((field (.ref (.ref GerbilAscentSessionContract 'responsibilities) '.run))
             (classifier (.ref field '.classify))
             (operation (lambda args (void))) (calls 0))
        (try
          (hash-put! (object-instance field) '.classify
            (lambda (candidate context)
              (set! calls (+ calls 1))
              (yuanxu-classification-evidence (.ref field 'identity) candidate #f [] context)))
          (check-equal? (with-catch (lambda (_failure) 'raised)
                          (lambda () (gerbil-ascent-make-session-value
                                       operation operation operation operation operation) 'accepted))
                        'raised)
          (check-equal? (> calls 0) #t)
          (finally (hash-put! (object-instance field) '.classify classifier)))))
    (test-case "Session publication preserves a changed public prototype"
      (let* ((prototype (.ref GerbilAscentSessionContract 'proto))
             (replacement (.o)) (operation (lambda args (void))))
        (try
          (.putslot! GerbilAscentSessionContract 'proto ($constant-slot-spec replacement))
          (let (session (gerbil-ascent-make-session-value operation operation operation operation operation))
            (check-equal? (element? GerbilAscentSessionContract session) #t)
            (check-equal? (.ref session '.run) operation))
          (finally (.putslot! GerbilAscentSessionContract 'proto ($constant-slot-spec prototype))))))
    (test-case "owned Relation field decisions equal the full public contract on current values"
      (for-each (lambda (position alternatives)
        (for-each (lambda (candidate)
          (let (arguments (vector (.ref GerbilAscentRelationContract 'proto)
                            'input 1 '((a)) [] #f
                            gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider))
            (vector-set! arguments position candidate)
            (let (relation (apply gerbil-ascent-make-relation-value (vector->list arguments)))
              (check-equal? (nested-relation? relation) (element? GerbilAscentRelationContract relation))))) alternatives))
        '(1 2 3 4 6 7)
        (list (list 'input #f 0 "input" []) (list 0 1 -1 1.5 #f)
              (list [] '((a)) '(a) (cons '(a) 'bad) #f #(a))
              (list [] (list (lambda (_) #t)) '(invalid) #f (cons (lambda (_) #t) 'bad))
              (list gerbil-ascent-hash-index-provider (.o (:: @ gerbil-ascent-hash-index-provider)) #f 0 [])
              (list gerbil-ascent-set-storage-provider (.o (:: @ gerbil-ascent-set-storage-provider)) #f 0 []))))
    (test-case "owned Relation values check current list contents without repeating caller predicates"
      (let* ((rows (list (list 1) (list 2))) (calls 0)
             (predicates (list (lambda (value) (set! calls (+ calls 1)) (exact-integer? value))))
             (relation (gerbil-ascent-relation 'input 1 rows
                         gerbil-ascent-hash-index-provider gerbil-ascent-set-storage-provider predicates)))
        (check-equal? calls 2)
        (check-equal? (nested-relation? relation) #t)
        (check-equal? (element? GerbilAscentRelationContract relation) #t)
        (check-equal? calls 2)
        (set-car! predicates 'invalid)
        (check-equal? (nested-relation? relation) #f)
        (check-equal? (element? GerbilAscentRelationContract relation) #f)
        (set-car! predicates (lambda (_) #t))
        (set-cdr! rows 'improper)
        (check-equal? (nested-relation? relation) #f)
        (check-equal? (element? GerbilAscentRelationContract relation) #f)))
    (test-case "caller Relation getters retain public demand order"
      (def (observe predicate)
        (let* ((seen [])
               (emit (lambda (key value) (set! seen (cons key seen)) value))
               (relation (.o (:: @ (.ref GerbilAscentRelationContract 'proto))
                 (name (emit 'name 'input)) (arity (emit 'arity 0)) (rows (emit 'rows []))
                 (field-predicates (emit 'predicates [])) (storage-kind (emit 'kind 'relation))
                 (index-provider (emit 'index gerbil-ascent-hash-index-provider))
                 (storage-provider (emit 'storage gerbil-ascent-set-storage-provider)))))
          (list (predicate relation) (reverse seen))))
      (let (expected (observe (cut element? GerbilAscentRelationContract <>)))
        (check-equal? (car expected) #t)
        (check-equal? (length (cadr expected)) 7)
        (check-equal? (observe nested-relation?) expected)))
    (test-case "edited producer Relation getters retain exact exceptions"
      (let ((relation (gerbil-ascent-relation 'input 1 '((a)))) (calls 0))
        (.putslot! relation 'rows ($thunk-slot-spec (lambda () (set! calls (+ calls 1)) (raise 'edited-relation))))
        (check-equal? calls 0)
        (check-equal? (with-catch (lambda (failure) failure) (lambda () (nested-relation? relation))) 'edited-relation)
        (check-equal? calls 1)
        (check-equal? (with-catch (lambda (failure) failure)
                        (lambda () (element? GerbilAscentRelationContract relation))) 'edited-relation)
        (check-equal? calls 2)))
    (test-case "Relation construction preserves live validation normalization"
      (let ((validator (.ref GerbilAscentRelationContract '.validate)) (sentinel (.o)) (calls 0))
        (try
          (hash-put! (object-instance GerbilAscentRelationContract) '.validate
            (lambda args (set! calls (+ calls 1)) sentinel))
          (check-equal? (gerbil-ascent-relation 'input 1 '((a))) sentinel)
          (check-equal? calls 1)
          (finally (hash-put! (object-instance GerbilAscentRelationContract) '.validate validator)))))
    (test-case "Relation construction retains every live field classifier"
      (for-each (lambda (slot)
        (let* ((field (.ref (.ref GerbilAscentRelationContract 'responsibilities) slot))
               (classifier (.ref field '.classify)) (calls 0))
          (try
            (hash-put! (object-instance field) '.classify
              (lambda (candidate context)
                (set! calls (+ calls 1))
                (yuanxu-classification-evidence (.ref field 'identity) candidate #f [] context)))
            (check-equal? (with-catch (lambda (_failure) 'raised)
                            (lambda () (gerbil-ascent-relation 'input 1 '((a))) 'accepted)) 'raised)
            (check-equal? (> calls 0) #t)
            (finally (hash-put! (object-instance field) '.classify classifier)))))
        '(name arity rows field-predicates storage-kind index-provider storage-provider)))
    (test-case "Relation construction honors root and field admission and obligation dispatch"
      (let (field (.ref (.ref GerbilAscentRelationContract 'responsibilities) 'rows))
        (for-each (lambda (descriptor)
          (for-each (lambda (slot)
            (let ((original (.ref descriptor slot)) (calls 0))
              (try
                (hash-put! (object-instance descriptor) slot
                  (lambda args (set! calls (+ calls 1)) (apply original args)))
                (let (relation (gerbil-ascent-relation 'input 1 '((a))))
                  (check-equal? (> calls 0) #t)
                  (check-equal? (element? GerbilAscentRelationContract relation) #t))
                (finally (hash-put! (object-instance descriptor) slot original)))))
            '(.admit .obligations))) (list GerbilAscentRelationContract field))))
    (test-case "custom providers enter complete admission once with identical callback order"
      (let* ((provider (.o (:: @ gerbil-ascent-hash-index-provider)))
             (classifier (.ref GerbilAscentIndexProviderContract '.classify))
             (seen []))
        (try
          (hash-put! (object-instance GerbilAscentIndexProviderContract) '.classify
            (lambda (candidate context) (set! seen (cons 'index seen)) (classifier candidate context)))
          (validate GerbilAscentRelationContract (plain-relation provider))
          (let (expected (reverse seen))
            (check-equal? (> (length expected) 0) #t)
            (set! seen [])
            (gerbil-ascent-relation 'input 1 '((a)) provider)
            (check-equal? (reverse seen) expected))
          (finally (hash-put! (object-instance GerbilAscentIndexProviderContract) '.classify classifier)))))
    (test-case "custom provider callbacks retain later obligation exceptions without duplicate effects"
      (let* ((provider (.o (:: @ gerbil-ascent-hash-index-provider)))
             (classifier (.ref GerbilAscentIndexProviderContract '.classify))
             (storage (.ref (.ref GerbilAscentRelationContract 'responsibilities) 'storage-provider))
             (obligations (.ref storage '.obligations)) (seen []))
        (def (observe construct)
          (set! seen [])
          (hash-put! (object-instance storage) '.obligations obligations)
          (let (answer (with-catch (lambda (failure) failure) (lambda () (construct) 'accepted)))
            (list answer (reverse seen))))
        (try
          (hash-put! (object-instance GerbilAscentIndexProviderContract) '.classify
            (lambda (candidate context)
              (set! seen (cons 'index seen))
              (hash-put! (object-instance storage) '.obligations
                (lambda args (set! seen (cons 'storage-obligation seen)) (raise 'later-storage-obligation)))
              (classifier candidate context)))
          (let (expected (observe (lambda () (validate GerbilAscentRelationContract (plain-relation provider)))))
            (check-equal? (car expected) 'later-storage-obligation)
            (check-equal? (and (memq 'index (cadr expected)) #t) #t)
            (check-equal? (observe (lambda () (gerbil-ascent-relation 'input 1 '((a)) provider))) expected))
          (finally
            (hash-put! (object-instance storage) '.obligations obligations)
            (hash-put! (object-instance GerbilAscentIndexProviderContract) '.classify classifier)))))
    (test-case "explicit contextual Relation admission retains all eight obligations"
      (let* ((seen []) (relation (gerbil-ascent-relation 'input 1 '((a))))
             (context (.o (.contract-obligations
                       (lambda (contract _candidate) (set! seen (cons (.ref contract 'identity) seen)) [])))))
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit GerbilAscentRelationContract relation context)) #t)
        (check-equal? (length seen) 8)
        (check-equal? (car seen) 'ascent/relation)))
    (test-case "nested membership retains complete element admission and obligation dispatch"
      (let* ((term (gerbil-ascent-variable 'x))
             (atom (gerbil-ascent-atom 'input (list term)))
             (relation (gerbil-ascent-relation 'input 1 '((a)))))
        (for-each (lambda (entry)
          (let ((contract (car entry)) (value (cadr entry)) (predicate (caddr entry)))
            (for-each (lambda (slot)
              (let ((original (.ref contract slot)) (calls 0))
                (try
                  (hash-put! (object-instance contract) slot
                    (lambda args (set! calls (+ calls 1)) (apply original args)))
                  (check-equal? (predicate value) #t)
                  (check-equal? (> calls 0) #t)
                  (finally (hash-put! (object-instance contract) slot original)))))
              '(.element? .admit .obligations))))
          (list (list GerbilAscentTermContract term nested-term?)
                (list GerbilAscentAtomContract atom
                  (lambda (value) (element? (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'heads) (list value))))
                (list GerbilAscentRelationContract relation nested-relation?)))))
    (test-case "a noncanonical Term admission cannot hide a later Atom obligation"
      (let* ((term (gerbil-ascent-variable 'x))
             (atom (gerbil-ascent-atom 'input (list term)))
             (admit (.ref GerbilAscentTermContract '.admit))
             (obligations (.ref GerbilAscentAtomContract '.obligations)) (seen []))
        (def (observe predicate)
          (set! seen [])
          (hash-put! (object-instance GerbilAscentAtomContract) '.obligations obligations)
          (let (answer (with-catch (lambda (failure) failure) (lambda () (predicate atom))))
            (list answer (reverse seen))))
        (try
          (hash-put! (object-instance GerbilAscentTermContract) '.admit
            (lambda (candidate context)
              (set! seen (cons 'term-admit seen))
              (let (evidence (admit candidate context))
                (hash-put! (object-instance GerbilAscentAtomContract) '.obligations
                  (lambda args (set! seen (cons 'atom-obligation seen)) (raise 'late-atom-obligation)))
                evidence)))
          (let (expected (observe (cut element? GerbilAscentAtomContract <>)))
            (check-equal? (car expected) 'late-atom-obligation)
            (check-equal? (and (memq 'term-admit (cadr expected)) #t) #t)
            (check-equal? (observe (lambda (value)
              (element? (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'heads) (list value)))) expected))
          (finally
            (hash-put! (object-instance GerbilAscentTermContract) '.admit admit)
            (hash-put! (object-instance GerbilAscentAtomContract) '.obligations obligations)))))
    (test-case "private publication does not reuse a stale shared Term admission"
      (let ((admit (.ref GerbilAscentTermContract '.admit)) (mutated? #f))
        (try
          (hash-put! (object-instance GerbilAscentTermContract) '.admit
            (lambda (candidate context)
              (let (evidence (admit candidate context))
                (unless mutated?
                  (set! mutated? #t)
                  (.putslot! candidate 'kind ($constant-slot-spec 'invalid-kind)))
                evidence)))
          (check-exception
            (gerbil-ascent-construct-inert-program
              (lambda ()
                (let (shared (gerbil-ascent-variable 'x))
                  (gerbil-ascent-program (list (gerbil-ascent-relation 'seed 1 '((0))))
                    (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom 'seed (list shared)))
                      (list (gerbil-ascent-atom 'seed (list shared))))) 8 8 16)))) true)
          (check-equal? mutated? #t)
          (finally (hash-put! (object-instance GerbilAscentTermContract) '.admit admit)))))
    (test-case "all kind classes and opaque values retain complete shape checks"
      (let (observed
             (observe-term
               (lambda (emit)
                 (.o (:: @ (.ref GerbilAscentTermContract 'proto))
                   (kind (emit 'kind 'variable)) (value (emit 'value 'x)))) nested-term?))
        (check-equal? (car observed) #t)
        (check-equal? (length (cadr observed)) 2))
      (for-each (lambda (tag)
        (compare-term (lambda (emit)
          (.o (:: @ (.ref GerbilAscentTermContract 'proto))
            (kind (emit 'kind tag))
            (value (emit 'value (lambda () (error "opaque value invoked"))))
            (unselected (error "unknown Term slot demanded"))))))
        '(variable wildcard literal expression pattern unknown #f 0 () "variable"))
      (for-each (lambda (value)
        (check-equal? (nested-term? value) (element? GerbilAscentTermContract value)))
        (list 0 #f [] "term" (vector 1) (lambda () (error "opaque non-Term invoked"))))
      (compare-term (lambda (emit)
        (.o (kind (emit 'kind 'variable)) (value (emit 'value 1)))))
      (compare-term (lambda (emit)
        (.o (:: @ (.ref GerbilAscentTermContract 'proto)) (kind (emit 'kind 'variable)))))
      (compare-term (lambda (emit)
        (.o (:: @ (.ref GerbilAscentTermContract 'proto)) (value (emit 'value 1))))))
    (test-case "getter failures and mutations retain demand and exception order"
      (compare-term (lambda (emit)
        (.o (:: @ (.ref GerbilAscentTermContract 'proto))
          (kind (begin (emit 'kind #f) (raise 'kind-getter-failure)))
          (value (emit 'value 1)))))
      (compare-term (lambda (emit)
        (.o (:: @ (.ref GerbilAscentTermContract 'proto))
          (kind (emit 'kind 'invalid))
          (value (begin (emit 'value #f) (raise 'value-getter-failure))))))
      (compare-term (lambda (emit)
        (let (cell (box 0))
          (.o (:: @ (.ref GerbilAscentTermContract 'proto))
            (kind (begin (set-box! cell 17) (emit 'kind 'variable)))
            (value (emit (list 'value (unbox cell)) (unbox cell))))))))
    (test-case "nested Atom membership retains full public shape and getter order"
      (let (heads (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'heads))
        (for-each (lambda (tag)
          (let (construct
                 (lambda (emit)
                   (.o (:: @ (.ref GerbilAscentAtomContract 'proto))
                     (ascent-clause-kind (emit 'kind tag))
                     (relation (emit 'relation 'input))
                     (terms (emit 'terms []))
                     (.plan (emit 'plan (lambda args (void))))
                     (unselected (error "unknown Atom slot demanded")))))
            (check-equal? (observe-term construct (lambda (atom) (element? heads (list atom))))
                          (observe-term construct (cut element? GerbilAscentAtomContract <>)))))
          '(atom invalid #f 0))
        (let (construct
               (lambda (emit)
                 (.o (:: @ (.ref GerbilAscentAtomContract 'proto))
                   (ascent-clause-kind (emit 'kind 'invalid))
                   (relation (begin (emit 'relation #f) (raise 'relation-getter-failure)))
                   (terms (emit 'terms [])) (.plan (lambda args (void))))))
          (check-equal? (observe-term construct (lambda (atom) (element? heads (list atom))))
                        (observe-term construct (cut element? GerbilAscentAtomContract <>))))))
    (test-case "every Atom responsibility remains required and typed"
      (let ((heads (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'heads))
            (fields (list (cons 'ascent-clause-kind 'atom) (cons 'relation 'input)
                          (cons 'terms []) (cons '.plan (lambda args (void))))))
        (def (compare atom)
          (check-equal? (element? heads (list atom)) (element? GerbilAscentAtomContract atom)))
        (for-each (lambda (missing)
          (compare
            (foldl (lambda (entry object) (.cc object (car entry) (cdr entry)))
              (.o (:: @ (.ref GerbilAscentAtomContract 'proto)))
              (filter (lambda (entry) (not (eq? (car entry) missing))) fields))))
          '(ascent-clause-kind relation terms .plan))
        (for-each (lambda (entry)
          (compare
            (foldl (lambda (field object)
                     (.cc object (car field)
                       (if (eq? (car field) (car entry)) (cdr entry) (cdr field))))
              (.o (:: @ (.ref GerbilAscentAtomContract 'proto))) fields)))
          '((relation . 7) (terms . #f) (terms 1) (.plan . 0)))))
    (test-case "explicit contextual Atom admission retains its complete responsibilities"
      (let* ((seen [])
             (context (.o (.contract-obligations
                        (lambda (contract _candidate)
                          (set! seen (cons (.ref contract 'identity) seen)) []))))
             (atom (.o (:: @ (.ref GerbilAscentAtomContract 'proto))
                       ascent-clause-kind: 'atom relation: 'input terms: []
                       .plan: (lambda args (void)))))
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit GerbilAscentAtomContract atom context)) #t)
        (check-equal? (length seen) 5)
        (check-equal? (car seen) 'ascent/atom)
        (check-equal? (and (memq 'ascent/terms seen) #t) #t)))
    (test-case "explicit contextual Term admission still invokes all obligations"
      (let* ((seen [])
             (context (.o (.contract-obligations
                        (lambda (contract _candidate)
                          (set! seen (cons (.ref contract 'identity) seen)) []))))
             (term (.o (:: @ (.ref GerbilAscentTermContract 'proto)) kind: 'variable value: 'x)))
        (check-equal? (nested-term? term) #t)
        (check-equal? seen [])
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit GerbilAscentTermContract term context)) #t)
        (check-equal? (length seen) 3)
        (check-equal? (and (memq 'ascent/term-kind seen) #t) #t)
        (check-equal? (and (memq 'ascent/value seen) #t) #t)
        (check-equal? (car seen) 'ascent/term)))
    (test-case "missing metadata cache entries take complete public admission"
      (let* ((term (gerbil-ascent-variable 'x))
             (kind (.ref (.ref GerbilAscentTermContract 'responsibilities) 'kind))
             (classifier (.ref kind '.classify))
             (cache (object-instance kind)))
        (try
          (hash-remove! cache '.classify)
          (check-equal? (hash-key? cache '.classify) #f)
          (check-equal? (nested-term? term) #t)
          ;; Complete fallback must run/repopulate the missing classifier.
          (check-equal? (hash-key? cache '.classify) #t)
          (finally (hash-put! cache '.classify classifier)))))
    (test-case "producer values remain checked and later edits restore full getter semantics"
      (let* ((term (gerbil-ascent-variable 'x))
             (atom (gerbil-ascent-atom 'input (list term)))
             (heads (.ref (.ref GerbilAscentRuleContract 'responsibilities) 'heads))
             (calls 0))
        (check-equal? (nested-term? term) #t)
        (check-equal? (element? heads (list atom)) #t)
        (.putslot! term 'kind
          ($thunk-slot-spec (lambda () (set! calls (+ calls 1)) (raise 'edited-term-getter))))
        (check-equal? calls 0)
        (check-equal? (with-catch (lambda (failure) failure) (lambda () (nested-term? term)))
                      'edited-term-getter)
        (check-equal? calls 1)
        (check-equal? (with-catch (lambda (failure) failure) (lambda () (element? heads (list atom))))
                      'edited-term-getter)))
    (test-case "deferred caller getters cannot bypass live later field obligations"
      (let* ((field (.ref (.ref GerbilAscentTermContract 'responsibilities) 'value))
             (classifier (.ref field '.classify))
             (term (.o (:: @ (.ref GerbilAscentTermContract 'proto)) kind: 'variable value: 'x))
             (calls 0))
        (.putslot! term 'kind
          ($thunk-slot-spec
            (lambda ()
              (set! calls (+ calls 1))
              (.putslot! field '.classify
                ($constant-slot-spec
                  (lambda (candidate context)
                    (yuanxu-classification-evidence (.ref field 'identity) candidate #f [] context))))
              'variable)))
        (check-equal? calls 0)
        (try
          (check-equal? (nested-term? term) #f)
          (check-equal? calls 1)
          (check-equal? (element? GerbilAscentTermContract term) #f)
          (finally (.putslot! field '.classify ($constant-slot-spec classifier))))))
    (test-case "live root and field classifier instrumentation remains authoritative"
      (let* ((term (.o (:: @ (.ref GerbilAscentTermContract 'proto)) kind: 'variable value: 'x))
             (kind (.ref (.ref GerbilAscentTermContract 'responsibilities) 'kind)))
        (for-each (lambda (descriptor)
          (let ((classifier (.ref descriptor '.classify)) (calls 0))
            (try
              (hash-put! (object-instance descriptor) '.classify
                (lambda (candidate context)
                  (set! calls (+ calls 1))
                  (yuanxu-classification-evidence (.ref descriptor 'identity)
                    candidate #f [] context)))
              (check-equal? (nested-term? term) #f)
              (check-equal? (> calls 0) #t)
              (finally (hash-put! (object-instance descriptor) '.classify classifier))))
          (check-equal? (nested-term? term) #t))
          (list GerbilAscentTermContract kind))))
    (test-case "supported field edits invalidate the canonical value view"
      (let* ((term (.o (:: @ (.ref GerbilAscentTermContract 'proto)) kind: 'variable value: 'x))
             (kind (.ref (.ref GerbilAscentTermContract 'responsibilities) 'kind))
             (classifier (.ref kind '.classify)))
        (try
          (.putslot! kind '.classify
            ($constant-slot-spec
              (lambda (candidate context)
                (yuanxu-classification-evidence (.ref kind 'identity) candidate #f [] context))))
          (check-equal? (nested-term? term) #f)
          (finally (.putslot! kind '.classify ($constant-slot-spec classifier))))
        (check-equal? (nested-term? term) #t)))))
