;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
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
