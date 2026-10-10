;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test check-equal? test-case test-suite)
        :gerbil-ascent/program/source-log
        :gerbil-ascent/t/performance/source-log/fixture
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/session gerbil-ascent-session-run
                 gerbil-ascent-session-replace-sources! gerbil-ascent-session-append-source!))
(export ascent-source-log-test)
(def (words depth)
  (if (zero? depth) (list [])
    (cons [] (foldr (lambda (word rest) (cons (cons '(#f) word) (cons (cons '(0) word) rest))) [] (words (- depth 1))))))
(def ascent-source-log-test
  (test-suite "Persistent ordered source logs"
    (test-case "675 finite cases retain exact order multiplicity and false values"
      (for-each
       (lambda (base)
         (for-each
          (lambda (additions)
            (let (expected (append base (reverse additions)))
              (check-equal? (gerbil-ascent-source-log-rows base additions) expected)
              (for-each
               (lambda (candidate)
                 (check-equal? (gerbil-ascent-source-log-equal? base additions candidate)
                               (equal? expected candidate)))
               (list expected (cons '(extra) expected) (if (pair? expected) (cdr expected) '((extra)))))))
          (words 3))) (words 3)))
    (test-case "read-only base reuse and detached appended headers preserve row identity"
      (let* ((row (list #f)) (last (list 2)) (base (list row)) (additions (list last))
             (joined (gerbil-ascent-source-log-rows base additions)))
        (check-equal? (eq? (gerbil-ascent-source-log-rows base []) base) #t)
        (check-equal? (eq? (car joined) row) #t)
        (check-equal? (eq? (cadr joined) last) #t)
        (set-car! joined '(changed))
        (check-equal? base (list row))
        (check-equal? additions (list last))))
    (test-case "public replacements retain appended sources and prior snapshots"
      (for-each
       (lambda (old?)
         (let* ((program (source-log-program 8 32))
                (session (source-log-request old? program #t))
                (prior (gerbil-ascent-session-run session))
                (before (source-log-result prior 8)))
           (for-each
            (lambda (_)
              (let (result (source-log-update session 8))
                (check-equal? (car result) #t)
                (check-equal? (list-ref (caddr result) 1) (append (map list (iota 32)) '((9999))))
                (check-equal? (drop (caddr result) 2) (make-list 6 (map list (iota 32)))))
              (check-equal? (source-log-result prior 8) before)) (iota 4))
           (let ((rows (list (list 55))))
             (gerbil-ascent-session-replace-sources! session (list (cons 'r0 rows)))
             (set-car! (car rows) 'mutated)
             (check-equal? ((.ref (gerbil-ascent-session-run session) 'rows-of) 'r0) '((55)))))) '(#t #f)))))
