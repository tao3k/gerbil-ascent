;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite test-case)
        (only-in :gerbil-ascent/candidate/types make-reasoning-candidate)
        (only-in :gerbil-ascent/candidate/certificate-limits
                 +max-certificate-relations+ +max-certificate-rows+
                 +max-certificate-cells+ +max-certificate-row-arity+
                 bounded-list-length unique-rows? certificate-for-each-while
                 make-certificate-material-budget certificate-material-reserve!)
        (only-in :gerbil-ascent/candidate/program-identity
                 candidate-finite-program-fingerprint
                 candidate-positive-program-fingerprint))
(export ascent-certificate-boundary-test)

(def (spec (query '(path 1 3)) (query-label 5) (fact-label 7)
           (rule-label 9) (limits '(12 32 32)) (relations '((path . 2))))
  (make-reasoning-candidate relations
    (list (vector 'path '(1 2) fact-label))
    (list (vector '(path ?x ?y) '((edge ?x ?y)) rule-label))
    (vector query query-label) limits))

(def ascent-certificate-boundary-test
  (test-suite "certificate material and identity boundaries"
    (test-case "refusal leaves the unread tail untouched and callbacks are not admission"
      (let ((live? #f) (seen []))
        ;; The disabled traversal must not even inspect an invalid input spine.
        (check-equal? (certificate-for-each-while (lambda () live?)
          (lambda (row) (error "unreachable visitor" row)) 'unread) #f)
        (set! live? #t)
        (check-equal? (certificate-for-each-while (lambda () live?)
          (lambda (row) (set! seen (cons row seen)) (set! live? #f))
          '(first . unread)) #f)
        (check-equal? seen '(first))
        ;; Duplicate/no-op callback results must not truncate live traversals.
        (set! live? #t)
        (set! seen [])
        (check-equal? (certificate-for-each-while (lambda () live?)
          (lambda (row) (set! seen (cons row seen)) #f) '(a b c)) #t)
        (check-equal? (reverse seen) '(a b c))))
    (test-case "nested work refusal stops every enclosing traversal"
      (let ((live? #t) (outer []) (inner []))
        (check-equal? (certificate-for-each-while (lambda () live?)
          (lambda (row)
            (set! outer (cons row outer))
            (certificate-for-each-while (lambda () live?)
              (lambda (item) (set! inner (cons item inner)) (set! live? #f))
              '(probe . unread))) '(branch . unread)) #f)
        (check-equal? outer '(branch))
        (check-equal? inner '(probe))))
    (test-case "material refusal is atomic and zero-width rows consume capacity"
      (let (budget (make-certificate-material-budget))
        (check-equal? (certificate-material-reserve! budget (make-list 1025 0)) #f)
        (for-each (lambda (_) (check-equal? (certificate-material-reserve! budget (make-list 1024 0)) #t)) (iota 32))
        (check-equal? (certificate-material-reserve! budget '(0)) #f)
        ;; Refusing one cell did not consume a row or corrupt full cell capacity.
        (for-each (lambda (i)
          (check-equal? (certificate-material-reserve! budget []) #t)
          (when (zero? (modulo (+ i 1) 512))
            (displayln "MATERIAL-ZERO-ROWS " (+ i 1)) (force-output))) (iota 4064))
        (check-equal? (certificate-material-reserve! budget []) #f)))
    (test-case "all finite lengths and caps preserve the admission boundary"
      (check-equal? (list +max-certificate-relations+ +max-certificate-rows+
                          +max-certificate-cells+ +max-certificate-row-arity+)
                    '(64 4096 32768 1024))
      (for-each
       (lambda (size)
         (let (items (iota size))
           (for-each
            (lambda (cap)
              (check-equal? (bounded-list-length items cap)
                            (and (<= size cap) size)))
            (iota 66)))
         (when (zero? (modulo size 16))
           (displayln "CERTIFICATE-LENGTH " size "/65") (force-output)))
       (iota 66))
      (check-equal? (bounded-list-length (iota 4096) 4096) 4096)
      (check-equal? (bounded-list-length (iota 4097) 4096) #f))
    (test-case "improper and cyclic spines terminate at the original cap"
      (check-equal? (bounded-list-length 'atom 16) #f)
      (check-equal? (bounded-list-length '(a b . tail) 16) #f)
      (let (cycle (list 'a 'b))
        (set-cdr! (cdr cycle) cycle)
        (check-equal? (bounded-list-length cycle 0) #f)
        (check-equal? (bounded-list-length cycle 4096) #f)
        (check-equal? (cddr cycle) cycle)))
    (test-case "row uniqueness uses structural equality and fresh state"
      (let ((first (list 1 2)) (equal-copy (list 1 2)))
        (check-equal? (eq? first equal-copy) #f)
        (check-equal? (unique-rows? (list first equal-copy)) #f)
        (check-equal? (unique-rows? (list first '(2 1))) #t)
        (check-equal? (unique-rows? '(() ())) #f)
        (check-equal? (unique-rows? []) #t)
        (check-equal? first '(1 2))))
    (test-case "historical identity bytes retain both certificate protocols"
      ;; Independent fixed digests of the historical wire datums; no call to
      ;; the new projection helpers is used to construct these goldens.
      (check-equal? (candidate-finite-program-fingerprint (spec))
                    "6874311303ba17e8518a625f1ef5f61998d843ce266245faa9fc15f82505e94d")
      (check-equal? (candidate-positive-program-fingerprint (spec))
                    "7fd56fb7fea154636c191b3647e93c26e0235bca825b9789c071d99fc4458724")
      (for-each
       (lambda (fingerprint)
         (let (original (fingerprint (spec)))
           (check-equal? (fingerprint (spec '(path 1 3) 99)) original)
           (for-each
            (lambda (changed) (check-equal? (equal? (fingerprint changed) original) #f))
            (list (spec '(path 1 4))
                  (spec '(path 1 3) 5 8)
                  (spec '(path 1 3) 5 7 10)
                  (spec '(path 1 3) 5 7 9 '(12 32 33))
                  (spec '(path 1 3) 5 7 9 '(12 32 32) '((path . 2) (extra . 1)))))))
       (list candidate-finite-program-fingerprint candidate-positive-program-fingerprint)))))
