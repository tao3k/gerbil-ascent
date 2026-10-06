;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref .o)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-rule gerbil-ascent-atom gerbil-ascent-variable
                 gerbil-ascent-guard gerbil-ascent-literal)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine gerbil-ascent-evaluate-program)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider
                 gerbil-ascent-eqrel-storage-provider gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider gerbil-ascent-storage-extension
                 gerbil-ascent-storage-engine-extension)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/admission gerbil-ascent-prepare-storage-batch)
        (only-in :gerbil-ascent/t/performance/storage-batch/reference old-prepare-storage-batch)
        :gerbil-ascent/t/performance/storage-batch/fixture
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run gerbil-ascent-session-append-source!))
(export ascent-storage-batch-test)
(def (prepare old? rows width present (check #f) (limit 100))
  (let-values (((accepted count) ((if old? old-prepare-storage-batch gerbil-ascent-prepare-storage-batch)
                                 rows width check present (hash-length present) limit)))
    (list accepted count)))
(def (failure call)
  (with-catch (lambda (e) (error-message e)) (lambda () (call) 'unexpected-success)))
(def (first-rows rows seen)
  (if (null? rows) []
    (if (member (car rows) seen)
      (first-rows (cdr rows) seen)
      (cons (car rows) (first-rows (cdr rows) (cons (car rows) seen))))))
(def ascent-storage-batch-test
  (test-suite "ASCENT complete storage batch admission"
    (test-case "interrupted Set source index publication requires engine source replay"
      (for-each
       (lambda (single?)
        (let* ((result-name (if single? 'input 'out))
               (reject? #f) (extensions 0)
             (provider
              (.o (:: @ gerbil-ascent-hash-index-provider)
                  (.extend-index!
                   (lambda (index rows columns)
                     (set! extensions (+ extensions 1))
                     (when reject?
                       (hash-clear! index)
                       (error "Set index publication failure"))
                     ((.ref gerbil-ascent-hash-index-provider '.extend-index!) index rows columns)))))
             (x (gerbil-ascent-variable 'x))
             (atom (gerbil-ascent-atom 'input (list (gerbil-ascent-literal 0) x)))
             (program
              (gerbil-ascent-program
               (cons (gerbil-ascent-relation 'input 2
                       (map (lambda (n) (list 0 n)) (iota 32)) provider)
                     (if single? [] (list (gerbil-ascent-relation 'out 1 []))))
               (list (gerbil-ascent-rule
                      (list (gerbil-ascent-atom result-name
                              (if single? (list (gerbil-ascent-literal 0) x) (list x)))) (list atom atom)))
               128 128 256))
             (engine (gerbil-ascent-make-engine program #t)))
        ((.ref engine '.run))
        ((.ref engine '.append-source!) 'input '(0 32))
        (set! reject? #t)
        (check-equal? (failure (lambda () ((.ref engine '.run)))) "Set index publication failure")
        (check-equal? (> extensions 0) #t)
        (set! reject? #f)
        (check-equal? (failure (lambda () ((.ref engine '.run))))
                      "ASCENT engine publication requires source replay")
        (check-equal? (failure (lambda () ((.ref engine '.append-source!) 'input '(0 33))))
                      "ASCENT engine publication requires source replay")
        ;; Checked Session reconstructs from the last committed source snapshot.
        (let* ((session (gerbil-ascent-open-session program))
               (old (gerbil-ascent-session-run session)))
          (gerbil-ascent-session-append-source! session 'input '(0 32))
          (set! reject? #t)
          (check-equal? (failure (lambda () (gerbil-ascent-session-run session)))
                        "Set index publication failure")
          (set! reject? #f)
          (check-equal? (length ((.ref (gerbil-ascent-session-run session) 'rows-of) result-name)) 32)
          (gerbil-ascent-session-append-source! session 'input '(0 32))
          (let (updated (gerbil-ascent-session-run session))
            (check-equal? (length ((.ref updated 'rows-of) result-name)) 33)
            (check-equal? (and (member (if single? '(0 32) '(32)) ((.ref updated 'rows-of) result-name)) #t) #t)
            (check-equal? (length ((.ref old 'rows-of) result-name)) 32)))))
       '(#f #t)))
    (test-case "native graph state cannot suppress facts after field rejection"
      (for-each
       (lambda (provider expected)
         (let* ((reject? #t) (calls 0)
                (predicate (lambda (_value)
                             (set! calls (+ calls 1))
                             (not (and reject? (> calls 2)))))
                (program (gerbil-ascent-program
                          (list (gerbil-ascent-relation 'input 2 []
                                  gerbil-ascent-hash-index-provider provider
                                  (list predicate predicate))) [] 16 16 64))
                (engine (gerbil-ascent-make-engine program #t)))
           ((.ref engine '.run))
           (check-equal? (failure (lambda () ((.ref engine '.append-source!) 'input '(1 2))))
                         "ASCENT relation field type mismatch")
           (set! reject? #f)
           (check-equal?
            (with-catch (lambda (e) (error-message e))
              (lambda ()
                ((.ref engine '.append-source!) 'input '(1 2))
                (storage-batch-rows ((.ref engine '.run)))))
            "ASCENT storage state requires source replay")
           (let (session (gerbil-ascent-open-session program))
             (gerbil-ascent-session-run session)
             (gerbil-ascent-session-append-source! session 'input '(1 2))
             (check-equal? (list-sort (lambda (a b)
                                       (or (< (car a) (car b))
                                           (and (= (car a) (car b)) (< (cadr a) (cadr b)))))
                                      (storage-batch-rows (gerbil-ascent-session-run session))) expected))))
       (list gerbil-ascent-eqrel-storage-provider gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)
       (list '((1 1) (1 2) (2 1) (2 2)) '((1 2)) '((1 1) (1 2) (2 2)))))
    (test-case "Session replay recovers native graph state after stored field rejection"
      (for-each
       (lambda (provider expected)
         (let* ((reject? #t) (calls 0)
                (predicate (lambda (_value)
                             (set! calls (+ calls 1))
                             (not (and reject? (> calls 2)))))
                (program (gerbil-ascent-program
                          (list (gerbil-ascent-relation 'input 2 []
                                  gerbil-ascent-hash-index-provider provider
                                  (list predicate predicate))) [] 16 16 64))
                (session (gerbil-ascent-open-session program))
                (first (gerbil-ascent-session-run session)))
           (check-equal? (failure (lambda () (gerbil-ascent-session-append-source! session 'input '(1 2))))
                         "ASCENT relation field type mismatch")
           (check-equal? (storage-batch-rows (gerbil-ascent-session-run session)) [])
           (set! reject? #f)
           (gerbil-ascent-session-append-source! session 'input '(1 2))
           (check-equal? (list-sort (lambda (a b)
                                     (or (< (car a) (car b))
                                         (and (= (car a) (car b)) (< (cadr a) (cadr b)))))
                                    (storage-batch-rows (gerbil-ascent-session-run session))) expected)
           (check-equal? (storage-batch-rows first) [])))
       (list gerbil-ascent-eqrel-storage-provider gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)
       (list '((1 1) (1 2) (2 1) (2 2)) '((1 2)) '((1 1) (1 2) (2 2)))))
    (test-case "native graph injections remain tentative through a later rule failure"
      (for-each
       (lambda (provider expected)
         (let* ((reject? #t) (calls 0)
                (x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
                (program (gerbil-ascent-program
                          (list (gerbil-ascent-relation 'source 2 '((1 2) (2 3)))
                                (gerbil-ascent-relation 'input 2 []
                                  gerbil-ascent-hash-index-provider provider))
                          (list (gerbil-ascent-rule
                                 (list (gerbil-ascent-atom 'input (list x y)))
                                 (list (gerbil-ascent-atom 'source (list x y))
                                       (gerbil-ascent-guard '(x y)
                                         (lambda (_x _y)
                                           (set! calls (+ calls 1))
                                           (when (and reject? (= calls 2))
                                             (error "later native guard failure")) #t)))))
                          16 32 64))
                (engine (gerbil-ascent-make-engine program #t)))
           (check-equal? (failure (lambda () ((.ref engine '.run)))) "later native guard failure")
           (set! reject? #f)
           (check-equal? (failure (lambda () ((.ref engine '.run))))
                         "ASCENT storage state requires source replay")
           (let (fresh (gerbil-ascent-make-engine program #t))
             (check-equal? (list-sort (lambda (a b)
                                       (or (< (car a) (car b))
                                           (and (= (car a) (car b)) (< (cadr a) (cadr b)))))
                                      (storage-batch-rows ((.ref fresh '.run)))) expected))))
       (list gerbil-ascent-eqrel-storage-provider gerbil-ascent-trrel-storage-provider
             gerbil-ascent-trrel-uf-storage-provider)
       (list (foldr append [] (map (lambda (a) (map (lambda (b) (list a b)) '(1 2 3))) '(1 2 3)))
             '((1 2) (1 3) (2 3)) '((1 1) (1 2) (1 3) (2 2) (2 3) (3 3)))))
    (test-case "failed mutable storage states require source replay before engine reuse"
      (for-each
       (lambda (mode)
         (let* ((reject? #t) (retained #f)
                (provider
                 (.o (:: @ gerbil-ascent-set-storage-provider)
                     (.make-state (lambda () (let (state (vector 0)) (set! retained state) state)))
                     (.extend-rows
                      (lambda (state _all _pending row _budget)
                        (let (already? (> (vector-ref state 0) 0))
                          (vector-set! state 0 1)
                          (if reject?
                            (case mode
                              ((raise) (error "mutated storage failure"))
                              ((shape) '((1 2))) ((field) '((bad)))
                              (else '((1) (2))))
                            (if already? [] (list row))))))))
                (program (gerbil-ascent-program
                          (list (gerbil-ascent-relation 'input 1 []
                                  gerbil-ascent-hash-index-provider provider (list integer?)))
                          [] 16 16 (if (eq? mode 'budget) 1 64)))
                (engine (gerbil-ascent-make-engine program #t)))
           (check-equal? (storage-batch-rows ((.ref engine '.run))) [])
           (check-equal? (failure (lambda () ((.ref engine '.append-source!) 'input '(1))))
                         (case mode
                           ((raise) "mutated storage failure")
                           ((shape) "invalid ASCENT storage provider row")
                           ((field) "ASCENT relation field type mismatch")
                           (else "ASCENT session output fact budget exceeded")))
           (check-equal? (vector-ref retained 0) 1)
           (set! reject? #f)
           ;; A successful-looking retry would omit the fact because private
           ;; state already records it. A fresh owner can admit the same row.
           (check-equal? (failure (lambda () ((.ref engine '.run))))
                         "ASCENT storage state requires source replay")
           (check-equal? (failure (lambda () ((.ref engine '.append-source!) 'input '(1))))
                         "ASCENT storage state requires source replay")
           (let (fresh (gerbil-ascent-make-engine program #t))
             ((.ref fresh '.run))
             ((.ref fresh '.append-source!) 'input '(1))
             (check-equal? (storage-batch-rows ((.ref fresh '.run))) '((1))))))
       '(raise shape field budget)))
    (test-case "Session source replay recovers mutable dispatch and admission failures"
      (for-each
       (lambda (mode)
         (let* ((reject? #t)
                (provider
                 (.o (:: @ gerbil-ascent-set-storage-provider)
                     (.make-state (lambda () (vector #f)))
                     (.extend-rows
                      (lambda (state _all _pending row _budget)
                        (let (prior (vector-ref state 0))
                          (vector-set! state 0 #t)
                          (if reject?
                            (case mode
                              ((raise) (error "mutated storage failure"))
                              ((shape) '((1 2))) ((field) '((bad)))
                              (else '((1) (2))))
                            (if prior [] (list row))))))))
                (program (gerbil-ascent-program
                          (list (gerbil-ascent-relation 'input 1 []
                                  gerbil-ascent-hash-index-provider provider (list integer?)))
                          [] 16 16 (if (eq? mode 'budget) 1 64)))
                (session (gerbil-ascent-open-session program))
                (first (gerbil-ascent-session-run session)))
           (check-equal? (failure (lambda () (gerbil-ascent-session-append-source! session 'input '(1))))
                         (case mode
                           ((raise) "mutated storage failure")
                           ((shape) "invalid ASCENT storage provider row")
                           ((field) "ASCENT relation field type mismatch")
                           (else "ASCENT session output fact budget exceeded")))
           (check-equal? (storage-batch-rows (gerbil-ascent-session-run session)) [])
           (set! reject? #f)
           (gerbil-ascent-session-append-source! session 'input '(1))
           (check-equal? (storage-batch-rows (gerbil-ascent-session-run session)) '((1)))
           (check-equal? (storage-batch-rows first) [])))
       '(raise shape field budget)))
    (test-case "a later guard failure keeps the entire custom storage round tentative"
      (let* ((calls 0) (reject? #t) (private #f)
             (provider
              (.o (:: @ gerbil-ascent-set-storage-provider)
                  (.make-state (lambda () (let (state (make-hash-table)) (set! private state) state)))
                  (.extend-rows
                   (lambda (state _all _pending row _budget)
                     (if (hash-get state row) []
                       (begin (hash-put! state row #t) (list row)))))))
             (x (gerbil-ascent-variable 'x))
             (program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'source 1 '((1) (2)))
                             (gerbil-ascent-relation 'input 1 []
                               gerbil-ascent-hash-index-provider provider))
                       (list (gerbil-ascent-rule
                              (list (gerbil-ascent-atom 'input (list x)))
                              (list (gerbil-ascent-atom 'source (list x))
                                    (gerbil-ascent-guard '(x)
                                      (lambda (_x)
                                        (set! calls (+ calls 1))
                                        (when (and reject? (= calls 2)) (error "later guard failure"))
                                        #t))))) 16 16 64))
             (engine (gerbil-ascent-make-engine program #t)))
        (check-equal? (failure (lambda () ((.ref engine '.run)))) "later guard failure")
        (check-equal? (hash-length private) 1)
        (set! reject? #f)
        (check-equal? (failure (lambda () ((.ref engine '.run))))
                      "ASCENT storage state requires source replay")
        (let (fresh (gerbil-ascent-make-engine program #t))
          (check-equal? (list-sort (lambda (a b) (< (car a) (car b)))
                                    (storage-batch-rows ((.ref fresh '.run)))) '((1) (2))))))
    (test-case "retained custom storage output rows cannot rewrite a published result"
      (let* ((emitted (list (list 1) (list 2)))
             (program (storage-batch-program 1 (lambda (_) emitted)))
             (first (storage-batch-engine-run #f program '(0))))
        (check-equal? (storage-batch-rows first) '((1) (2)))
        (set-car! (car emitted) 99)
        (set-cdr! emitted [])
        (check-equal? (storage-batch-rows first) '((1) (2)))))
    (test-case "custom storage owns borrowed all pending and input row spines"
      (let* ((captured [])
             (provider
              (.o (:: @ gerbil-ascent-set-storage-provider)
                  (.extend-rows
                   (lambda (_state all pending row _budget)
                     (set! captured (cons (list all pending row) captured))
                     (list row)))))
             (source (list (list 1) (list 2)))
             (program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'input 1 source
                               gerbil-ascent-hash-index-provider provider)) [] 16 16 64))
             (engine (gerbil-ascent-make-engine program #t))
             (run (.ref engine '.run))
             (first (run)))
        (check-equal? (storage-batch-rows first) '((1) (2)))
        (for-each
         (lambda (args)
           (for-each
            (lambda (rows)
              (when (pair? rows) (set-car! (car rows) 99) (set-cdr! rows [])))
            (take args 2))
           (set-car! (list-ref args 2) 99))
         captured)
        (check-equal? source '((1) (2)))
        (check-equal? (storage-batch-rows first) '((1) (2)))
        ((.ref engine '.append-source!) 'input '(3))
        (check-equal? (storage-batch-rows (run)) '((1) (2) (3)))
        (check-equal? (storage-batch-rows first) '((1) (2)))))
    (test-case "rule-produced custom storage rows remain detached after materialization"
      (let* ((retained [])
             (provider (.o (:: @ gerbil-ascent-set-storage-provider)
                           (.extend-rows
                            (lambda (_state _all _pending row _budget)
                              (set! retained (cons row retained)) (list row)))))
             (x (gerbil-ascent-variable 'x))
             (program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'source 1 '((1) (2)))
                             (gerbil-ascent-relation 'input 1 []
                               gerbil-ascent-hash-index-provider provider))
                       (list (gerbil-ascent-rule
                              (list (gerbil-ascent-atom 'input (list x)))
                              (list (gerbil-ascent-atom 'source (list x)))))
                       16 16 64))
             (result (gerbil-ascent-evaluate-program program)))
        (check-equal? (storage-batch-rows result) '((1) (2)))
        (for-each (lambda (row) (set-car! row 99)) retained)
        (check-equal? (storage-batch-rows result) '((1) (2)))))
    (test-case "custom shape preflight rejects malformed packets before stored field callbacks"
      (let ((cycle (list 1)) (outer (list '(2))))
        (set-cdr! cycle cycle) (set-cdr! outer outer)
        (for-each
         (lambda (batch)
           (let* ((calls 0)
                  (provider (storage-batch-provider (lambda (_) batch)))
                  (program (gerbil-ascent-program
                            (list (gerbil-ascent-relation 'input 1 []
                                    gerbil-ascent-hash-index-provider provider
                                    (list (lambda (_) (set! calls (+ calls 1)) #t))))
                            [] 16 16 64))
                  (engine (gerbil-ascent-make-engine program #t)))
             (check-equal? (storage-batch-rows ((.ref engine '.run))) [])
             (check-equal? (failure (lambda () ((.ref engine '.append-source!) 'input '(0))))
                           (if (list? batch) "invalid ASCENT storage provider row"
                             "ASCENT storage provider returned non-list rows"))
             ;; The input row is checked once; no returned row reaches a checker.
             (check-equal? calls 1)
             (check-equal? (failure (lambda () ((.ref engine '.run))))
                           "ASCENT storage state requires source replay")))
         (list 7 outer (list '(2) '(3 4)) (list '(2) '(3 . 4)) (list '(2) cycle)))))
    (test-case "native storage dispatch stays direct and derived receivers own spines"
      (for-each
       (lambda (provider)
         (check-equal? (eq? (gerbil-ascent-storage-extension provider 3)
                            (.ref provider '.extend-rows)) #t)
         (check-equal? (eq? (gerbil-ascent-storage-engine-extension provider 3)
                            (.ref provider '.extend-rows))
                       (eq? provider gerbil-ascent-set-storage-provider))
         (let (derived (.o (:: @ provider)))
           (check-equal? (eq? (gerbil-ascent-storage-extension derived 3)
                              (.ref derived '.extend-rows)) #f)))
       (list gerbil-ascent-set-storage-provider gerbil-ascent-eqrel-storage-provider
             gerbil-ascent-trrel-storage-provider gerbil-ascent-trrel-uf-storage-provider))
      (let* ((field (vector 'stable)) (all (list (list field)))
             (provider (.o (:: @ gerbil-ascent-set-storage-provider)
                           (.extend-rows
                            (lambda (_state rows pending row _budget)
                              (check-equal? (eq? rows pending) #t)
                              (check-equal? (eq? rows all) #f)
                              (check-equal? (eq? (caar rows) field) #t)
                              (list row)))))
             (answer ((gerbil-ascent-storage-extension provider 1) #f all all (list field) 4)))
        (check-equal? (eq? (caar answer) field) #t)))
    (test-case "finite duplicate traces match independent first-row filtering"
      (for-each
       (lambda (mask)
         (let (present (make-hash-table))
           (for-each (lambda (n) (when (odd? (quotient mask (expt 2 n))) (hash-put! present (list n) #t))) (iota 3))
           (for-each
            (lambda (code)
              (let* ((rows (map (lambda (shift) (list (modulo (quotient code (expt 3 shift)) 3))) (iota 5)))
                     (expected (filter (lambda (row) (not (hash-get present row))) (first-rows rows [])))
                     (answer (prepare #f rows 1 present)))
                (check-equal? answer (list expected (length expected)))
                (check-equal? answer (prepare #t rows 1 present))
                (check-equal? (hash-length present) (length (filter (lambda (n) (odd? (quotient mask (expt 2 n)))) (iota 3))))))
            (iota 243)))) (iota 8)))
    (test-case "provider headers and first accepted row identities remain owned"
      (let* ((first (list #f 1)) (same (list #f 1)) (last (list #t 2))
             (rows (list first same last)) (present (make-hash-table))
             (answer (car (prepare #f rows 2 present))))
        (check-equal? (eq? (car answer) first) #t)
        (check-equal? (eq? (cadr answer) last) #t)
        (check-equal? (eq? answer rows) #f)
        (set-cdr! answer [])
        (check-equal? rows (list first same last))
        (check-equal? (hash-length present) 0)))
    (test-case "all duplicate callbacks precede budget rejection without publication"
      (for-each
       (lambda (old?)
         (let ((events []) (present (make-hash-table)))
           (hash-put! present '(0) #t)
           (check-equal? (failure (lambda () (prepare old? '((1) (1) (0) (2)) 1 present
                          (lambda (row) (set! events (cons row events))) 1)))
                         "ASCENT session output fact budget exceeded")
           (check-equal? (reverse events) '((1) (1) (0) (2)))
           (check-equal? (hash->list present) '(((0) . #t))))) '(#t #f)))
    (test-case "late malformed rows checker failures and cyclic batches reject"
      (for-each
       (lambda (old?)
         (for-each
          (lambda (rows)
            (let ((events []) (present (make-hash-table)))
              (check-equal? (failure (lambda () (prepare old? rows 1 present
                               (lambda (row) (set! events (cons row events))))))
                            "invalid ASCENT storage provider row")
              (check-equal? (reverse events) '((1)))
              (check-equal? (hash-length present) 0)))
          (list '((1) (2 3)) (list '(1) (cons 2 3))))
         (let ((present (make-hash-table)) (cyclic (list '(1))))
           (set-cdr! cyclic cyclic)
           (check-equal? (failure (lambda () (prepare old? cyclic 1 present)))
                         "ASCENT storage provider returned non-list rows")
           (check-equal? (failure (lambda () (prepare old? '((1) (2)) 1 present
                              (lambda (row) (when (= (car row) 2) (error "planned row rejection"))))))
                         "planned row rejection")
           (check-equal? (hash-length present) 0))) '(#t #f)))
    (test-case "complete engine batches preserve ordered publication and provider lists"
      (for-each
       (lambda (size)
         (let* ((rows (map list (iota size))) (batch (append rows rows))
                (program (storage-batch-program 1 (lambda (_) batch))))
           (for-each
            (lambda (old?)
              (check-equal? (storage-batch-rows (storage-batch-engine-run old? program '(0))) rows)
              (check-equal? batch (append rows rows))) '(#t #f)))) '(0 1 32 256)))
    (test-case "custom providers observe separate all and delta headers on later appends"
      (for-each
       (lambda (old?)
         (let* ((trace [])
                (program (storage-batch-program 1 (lambda (_) '((1) (2))) 8192
                          (lambda (all delta) (set! trace (cons (eq? all delta) trace))))))
           (check-equal? (storage-batch-rows (storage-batch-engine-run old? program '(0) 2)) '((1) (2)))
           (check-equal? (reverse trace) '(#t #f)))) '(#t #f)))
    (test-case "retained recovery rejects failed batches then accepts later updates"
      (let* ((bad? #f) (batch '((1) (2)))
             (session (gerbil-ascent-open-session
                       (storage-batch-program 1 (lambda (_) (if bad? '((1) (2 3)) batch)))))
             (initial (gerbil-ascent-session-run session)))
        (set! bad? #t)
        (check-equal? (failure (lambda () (gerbil-ascent-session-append-source! session 'input '(0))))
                      "invalid ASCENT storage provider row")
        (check-equal? (storage-batch-rows (gerbil-ascent-session-run session)) [])
        (set! bad? #f)
        (gerbil-ascent-session-append-source! session 'input '(0))
        (let (first (gerbil-ascent-session-run session))
          (check-equal? (storage-batch-rows first) '((1) (2)))
          (set! batch '((2) (3) (3)))
          (gerbil-ascent-session-append-source! session 'input '(0))
          (check-equal? (storage-batch-rows (gerbil-ascent-session-run session)) '((1) (2) (3)))
          (check-equal? (storage-batch-rows first) '((1) (2))))
        (check-equal? (storage-batch-rows initial) [])))))
