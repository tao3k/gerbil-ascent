;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .cc .ref .putslot! object-instance $constant-slot-spec $thunk-slot-spec)
        (only-in :clan/poo/mop element?)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?
                 poo-flow-classification-evidence)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-variable gerbil-ascent-atom)
        (only-in :gerbil-ascent/program/types GerbilAscentTermContract GerbilAscentAtomContract GerbilAscentRuleContract))
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

(def ascent-value-membership-test
  (test-suite "Nested value membership preserves public admission"
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
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit GerbilAscentAtomContract atom context)) #t)
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
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit GerbilAscentTermContract term context)) #t)
        (check-equal? (length seen) 3)
        (check-equal? (and (memq 'ascent/term-kind seen) #t) #t)
        (check-equal? (and (memq 'ascent/value seen) #t) #t)
        (check-equal? (car seen) 'ascent/term)))
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
                    (poo-flow-classification-evidence (.ref field 'identity) candidate #f [] context))))
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
                  (poo-flow-classification-evidence (.ref descriptor 'identity)
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
                (poo-flow-classification-evidence (.ref kind 'identity) candidate #f [] context))))
          (check-equal? (nested-term? term) #f)
          (finally (.putslot! kind '.classify ($constant-slot-spec classifier))))
        (check-equal? (nested-term? term) #t)))))
