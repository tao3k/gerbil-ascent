;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test "oracle.ss")
(export finite-choice-oracle-test)

;; Enumerate all partial assignments over a two-attribute, two-value domain.
;; Check each proposed solution backwards by removing a supported assignment.
;; This takes a different route from following forward rule successors.
(def (all-databases)
  (foldr (lambda (first tail)
           (foldr (lambda (second tail)
                    (cons (append (if first (list (cons 0 first)) [])
                                  (if second (list (cons 1 second)) []))
                          tail))
                  tail '(#f 0 1)))
         [] '(#f 0 1)))

(def (satisfied? database body)
  (andmap (lambda (fact) (member fact database)) body))

(def (expected-solutions rules)
  (def (supported? database)
    (or (null? database)
        (ormap (lambda (fact)
                 (let (prior (filter (lambda (row) (not (equal? row fact))) database))
                   (and (ormap (lambda (rule)
                                  (match rule
                                    ([kind attribute offer body]
                                     (and (= attribute (car fact))
                                          (if (eq? kind 'open) (= offer (cdr fact))
                                            (memv (cdr fact) offer))
                                          (satisfied? prior body))))) rules)
                        (supported? prior))))
               database)))
  (filter (lambda (database)
            (and (andmap (lambda (rule)
                           (match rule
                             ([kind attribute offer body]
                              (or (not (satisfied? database body))
                                  (let (known (assv attribute database))
                                    (and known (or (eq? kind 'open) (memv (cdr known) offer))))))))
                         rules)
                 (supported? database)))
          (all-databases)))

(def (check-program rules expected)
  (let (actual (finite-choice-solutions rules void))
    (check-equal? (length actual) (length expected))
    (check-equal? (andmap (lambda (database) (and (member database actual) #t)) expected) #t)))

(def finite-choice-oracle-test
  (test-suite "Finite-choice ground fact-set semantics"
    (test-case "open stutter cannot publish an unset attribute"
      (check-program '((open 0 1 ())) '(((0 . 1))))
      (check-program '((open 0 1 ()) (open 0 0 ())) '(((0 . 0)) ((0 . 1)))))
    (test-case "closed intersection and conflict"
      (check-program '((closed 0 (0 1) ()) (closed 0 (1 2) ())) '(((0 . 1))))
      (check-program '((closed 0 (0) ()) (closed 0 (1) ())) [])
      (check-program '((closed 0 () ())) []))
    (test-case "siblings preserve distinct consequences and discard invalid branches"
      (check-program '((closed 0 (0 1) ()) (closed 1 (1) ((0 . 0)))
                       (closed 1 () ((0 . 1))))
                     '(((0 . 0) (1 . 1)))))
    (test-case "unsupported cycles introduce no facts"
      (check-program '((closed 0 (0) ((1 . 1))) (closed 1 (1) ((0 . 0)))) '(())))
    (test-case "256 finite programs and their reversed rule order"
      (let (catalog '((closed 0 (0 1) ()) (open 0 0 ()) (open 0 1 ())
                      (closed 1 (0) ((0 . 0))) (closed 1 (1) ((0 . 1)))
                      (open 1 1 ((0 . 0))) (closed 0 (0) ((1 . 1)))
                      (closed 1 () ((0 . 1) (1 . 1)))))
        (for-each
          (lambda (mask)
            (let* ((rules (filter-map (lambda (rule index) (and (bit-set? index mask) rule))
                                      catalog (iota 8)))
                   (expected (expected-solutions rules)))
              (check-program rules expected)
              (check-program (reverse rules) expected)))
          (iota 256))))
    (test-case "interruption propagates even after an answer was found"
      (let ((work 0) (failure (list 'interrupted)))
        (check-eq?
         (with-catch values
           (lambda ()
             (finite-choice-solutions '((closed 0 (0 1) ()))
               (lambda ()
                 (set! work (+ work 1))
                 (when (= work 8) (raise failure))))))
         failure)))
    (test-case "malformed ground programs are rejected"
      (check-exception (finite-choice-solutions '((open -1 1 ())) void) true)
      (check-exception (finite-choice-solutions '((closed 0 (x) ())) void) true))))
