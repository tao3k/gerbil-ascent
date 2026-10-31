;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :gerbil-ascent/program/summary
        (prefix-in :gerbil-ascent/t/performance/declaration-summary/reference old-))
(export summary-input summary-workflow summary-expected summary-data)
(def (summary-data summary)
  (map (lambda (component)
         (list (.ref component 'rules) (.ref component 'dynamic-relations) (.ref component 'is-looping)))
       (.ref summary 'sccs)))
(def (summary-input width count shape)
  (def (name n) (string->symbol (string-append "r" (number->string n))))
  (def (head n) (.o (relation (name n))))
  (def (read n kind) (.o (relation (name n)) (ascent-clause-kind kind)))
  (let* ((declarations
          (map (lambda (n)
                 (.o
                  (heads (case shape
                           ((chain isolated) (list (head n)))
                           ((dense) (map head (iota width)))
                           (else (make-list width (head 0)))))
                  (body (case shape
                          ((chain) (if (zero? n) [] (list (read (- n 1) 'atom))))
                          ((isolated) (list (.o (ascent-clause-kind 'guard))))
                          ((dense) (map (lambda (i) (read (modulo i width) 'atom)) (iota (* width 2))))
                          (else (make-list (* width 2) (read 0 'atom))))))) (iota count)))
         (expected
          (if (zero? count) []
            (case shape
              ((chain isolated)
               (map (lambda (n) (list (list n) (list (name n)) #f))
                    (if (eq? shape 'isolated) (reverse (iota count)) (iota count))))
              (else (list (list (iota count)
                               (if (eq? shape 'dense)
                                 (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
                                            (map name (iota width)))
                                 (list (name 0))) #t)))))))
    (vector (.o (rules declarations)) expected)))
(def (summary-workflow old? input)
  (summary-data ((if old? old-gerbil-ascent-program-summary gerbil-ascent-program-summary) (vector-ref input 0))))
(def (summary-expected input) (vector-ref input 1))
