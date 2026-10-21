;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .o .ref .all-slots object-instance)
        (only-in :clan/poo/mop validate)
        :gerbil-ascent/program/operator
        (prefix-in :gerbil-ascent/t/performance/operator-publication/reference old-)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-fragment gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-literal gerbil-ascent-guard
                 gerbil-ascent-construct-inert-program gerbil-ascent-construct-inert-fragment)
        (only-in :gerbil-ascent/program/types GerbilAscentProgramContract GerbilAscentFragmentContract)
        :gerbil-ascent/t/performance/operator-publication/fixture)
(export ascent-operator-publication-test)
(def (immediate-check!)
  (check-exception (gerbil-ascent-variable 99) true)
  ;; These failures belong to recursive declaration contracts, rather than
  ;; primitive constructor preconditions: an inert extent would skip them.
  (check-exception (gerbil-ascent-rule '(99) []) true)
  (check-exception (gerbil-ascent-relation 'bad 1 '((0)) #f) true))
(def ascent-operator-publication-test
  (test-suite "Canonical Operator root admission and open constructor contracts"
    (test-case "complete mixed graphs Programs Fragments cold and controls match frozen consumers"
      (for-each (lambda (scenario)
        (let ((old (publication-prepare #t scenario)) (new (publication-prepare #f scenario)))
          (check-equal? (publication-consume new scenario #f) (publication-consume old scenario #t))
          (publication-verify! old scenario #t) (publication-verify! new scenario #f)))
        '(program fragment cold custom small empty)))
    (test-case "root contracts remain complete and public constructors stay immediate"
      (let (root (relational-op-source 'seed 1 '((0))))
        (let-values (((program output) (relational-op-compile root 8 8 16)))
          (check-equal? (eq? (validate GerbilAscentProgramContract program) program) #t)
          (immediate-check!))
        (let (fragment (relational-op-fragment root 'answer))
          (check-equal? (eq? (validate GerbilAscentFragmentContract fragment) fragment) #t)
          (immediate-check!))))
    (test-case "publication uses the exact public root prototype responsibilities and validation dispatch"
      (for-each (lambda (parent)
        (let ((validator (.ref parent '.validate)) (prototype (.ref parent 'proto))
              (slots (.all-slots (.ref parent 'responsibilities))) (calls 0))
          (try
            (hash-put! (object-instance parent) '.validate
              (lambda (candidate)
                (set! calls (+ calls 1))
                (check-equal? (eq? (.ref parent 'proto) prototype) #t)
                (check-equal? (.all-slots (.ref parent 'responsibilities)) slots)
                (immediate-check!)
                (validator candidate)))
            (let (value
                  (if (eq? parent GerbilAscentProgramContract)
                    (gerbil-ascent-construct-inert-program
                      (lambda () (gerbil-ascent-program
                        (list (gerbil-ascent-relation 'seed 1 '((0)))) [] 8 8 16)))
                    (gerbil-ascent-construct-inert-fragment
                      (lambda () (gerbil-ascent-fragment
                        (list (gerbil-ascent-relation 'seed 1 '((0)))) [] '((answer . seed)) '(seed))))))
              (check-equal? calls 1)
              (check-equal? (eq? (validator value) value) #t))
            (finally (hash-put! (object-instance parent) '.validate validator)))))
        (list GerbilAscentProgramContract GerbilAscentFragmentContract)))
    (test-case "final inert publication retains the public rules classifier"
      (let* ((field (.ref (.ref GerbilAscentProgramContract 'responsibilities) 'rules))
             (classifier (.ref field '.classify)) (calls 0))
        (try
          (hash-put! (object-instance field) '.classify
            (lambda args (set! calls (+ calls 1)) (raise 'public-rules-classifier)))
          (check-equal? (with-catch (lambda (failure) failure)
            (lambda () (gerbil-ascent-construct-inert-program
              (lambda () (gerbil-ascent-program
                (list (gerbil-ascent-relation 'seed 1 []))
                (list (gerbil-ascent-rule
                  (list (gerbil-ascent-atom 'seed (list (gerbil-ascent-variable 'x))))
                  (list (gerbil-ascent-atom 'seed (list (gerbil-ascent-variable 'x)))))) 8 8 16)))))
            'public-rules-classifier)
          (check-equal? calls 1)
          (finally (hash-put! (object-instance field) '.classify classifier)))))
    (test-case "a new publication rechecks a previously published shared Term identity"
      (let (shared #f)
        (def (produce)
          (gerbil-ascent-construct-inert-program
            (lambda ()
              (unless shared (set! shared (gerbil-ascent-variable 'x)))
              (gerbil-ascent-program
                (list (gerbil-ascent-relation 'seed 1 '((0))))
                (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'seed (list shared)))
                                         (list (gerbil-ascent-atom 'seed (list shared)))))
                8 8 16))))
        (let (program (produce))
          (check-equal? (eq? (validate GerbilAscentProgramContract program) program) #t))
        (hash-put! (object-instance shared) 'kind 'invalid-kind)
        (check-exception (produce) true)
        (immediate-check!)))
    (test-case "inert root admission rejects malformed Terms and retains nonatom contracts without callbacks"
      (check-exception
       (gerbil-ascent-construct-inert-program
        (lambda ()
          (gerbil-ascent-program (list (gerbil-ascent-relation 'seed 1 []))
            (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'seed '(99))) [])) 8 8 16))) true)
      (let ((calls 0) (program #f))
        (set! program
          (gerbil-ascent-construct-inert-program
            (lambda ()
              (gerbil-ascent-program (list (gerbil-ascent-relation 'answer 1 []))
                (list (gerbil-ascent-rule
                        (list (gerbil-ascent-atom 'answer (list (gerbil-ascent-literal 0))))
                        (list (gerbil-ascent-guard [] (lambda () (set! calls (+ calls 1)) #t)))))
                8 8 16))))
        (check-equal? (eq? (validate GerbilAscentProgramContract program) program) #t)
        (check-equal? calls 0)))
    (test-case "any custom constructor observes immediate checks in both inherited methods"
      (let* ((calls [])
             (root (relational-op-project (relational-op-source 'seed 2 '((0 1))) '(1 0)))
             (relation-owner (.o (:: @ relational-op-compiler)
               (.make-relation (lambda args (immediate-check!) (set! calls (cons 'relation calls))
                                  (apply gerbil-ascent-relation args)))))
             (rule-owner (.o (:: @ relational-op-compiler)
               (.make-rule (lambda args (immediate-check!) (set! calls (cons 'rule calls))
                              (apply gerbil-ascent-rule args)))))
             (program-owner (.o (:: @ relational-op-compiler)
               (.make-program (lambda args (immediate-check!) (set! calls (cons 'program calls))
                                 (apply gerbil-ascent-program args)))))
             (fragment-owner (.o (:: @ relational-op-compiler)
               (.make-fragment (lambda args (immediate-check!) (set! calls (cons 'fragment calls))
                                  (apply gerbil-ascent-fragment args))))))
        (.ref relational-op-compiler '.compile) (.ref relational-op-compiler '.fragment)
        (for-each (lambda (owner)
          (set! calls [])
          (relational-op-compile root 8 8 16 owner)
          (check-equal? (pair? calls) #t)) (list relation-owner rule-owner program-owner))
        (for-each (lambda (owner)
          (set! calls [])
          (relational-op-fragment root 'answer owner)
          (check-equal? (pair? calls) #t)) (list relation-owner rule-owner fragment-owner))))
    (test-case "failed graph admission invokes no constructor and restores ordinary checks"
      (let* ((calls 0) (root (relational-op-source 'seed 1 '((0))))
             (owner (.o (:: @ relational-op-compiler)
               (.make-relation (lambda args (set! calls (+ calls 1))
                                  (apply gerbil-ascent-relation args))))))
        (set-car! (vector-ref (relational-op-data root) 1) '(0 1))
        (check-exception (relational-op-compile root 8 8 16) true)
        (check-exception (relational-op-fragment root 'answer) true)
        (check-exception (relational-op-compile root 8 8 16 owner) true)
        (check-exception (relational-op-fragment root 'answer owner) true)
        (check-equal? calls 0) (immediate-check!)))
    (test-case "fresh Fragment handles and detached input rows survive repeated publication"
      (let* ((root (relational-op-source 'seed 1 '((0))))
             (first (relational-op-fragment root 'answer))
             (second (relational-op-fragment root 'answer)))
        (check-equal? (eq? ((.ref first 'exports) 'seed) ((.ref second 'exports) 'seed)) #f)
        (set-car! (car (vector-ref (relational-op-data root) 1)) 1)
        (check-equal? (.ref (car (.ref first 'relations)) 'rows) '((0)))
        (check-equal? (.ref (car (.ref second 'relations)) 'rows) '((0)))))
    (test-case "a construction failure after the first source restores recursive contracts"
      (let (root (relational-op-join (relational-op-source 'seed 1 '((0)))
                                    (relational-op-source 'seed 1 '((1))) 0 0))
        (check-exception (relational-op-compile root 8 8 16) true)
        (immediate-check!)
        (check-exception (relational-op-fragment root 'answer) true)
        (immediate-check!)))
    (test-case "projection columns preserve every binding including repeated empty and nullary layouts"
      (for-each (lambda (width)
        (let ((row (iota width))
              (columns (if (zero? width) '(())
                         (list [] (iota width) (reverse (iota width)) (append (iota width) (iota width))))))
          (for-each (lambda (selected)
            (let (root (relational-op-project (relational-op-source 'seed width (list row)) selected))
              (let-values (((a x) (old-relational-op-compile root 8 8 16))
                           ((b y) (relational-op-compile root 8 8 16)))
                (check-equal? (publication-shape a x) (publication-shape b y))))) columns)))
        (iota 5)))))
