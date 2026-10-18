;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The installed engine reads inert ASCENT declarations. No import, eval,
;;; macro expansion, compiler, or caller-supplied Scheme callback is involved.
(import :std/encoding/json
        (only-in :gerbil/runtime/gambit
                 current-readtable readtable-eval-allowed?-set
                 readtable-sharing-allowed?-set))
(export ascent-read-rule-sources)

(def (wire-name value)
  (unless (and (symbol? value) (< 0 (string-length (symbol->string value)) 129))
    (error "invalid ASCENT rule name" value))
  (symbol->string value))

(def (proper value)
  (unless (and (list? value) (<= (length value) 256))
    (error "bounded proper ASCENT form required"))
  value)

(def (wire-literal value)
  (cond ((and (list? value) (= (length value) 2) (eq? (car value) 'quote)
              (symbol? (cadr value))) (wire-name (cadr value)))
        ((or (exact-integer? value) (boolean? value) (string? value)) value)
        (else (error "inert ASCENT scalar literal required" value))))

(def (wire-term value)
  (cond ((eq? value '_) (error "wildcard transport is not supported by this native wire"))
        ((symbol? value) (hash ("var" (wire-name value))))
        ((and (list? value) (= (length value) 2) (eq? (car value) 'lit))
         (hash ("const" (wire-literal (cadr value)))))
        ((or (exact-integer? value) (boolean? value) (string? value))
         (hash ("const" value)))
        (else (error "unsupported inert ASCENT term" value))))

(def (wire-atom value (negative #f))
  (proper value)
  (unless (and (pair? value) (<= (length (cdr value)) 16))
    (error "ASCENT atom column bound"))
  (hash ("relation" (wire-name (car value)))
        ("terms" (map wire-term (cdr value))) ("not" negative)))

(def (wire-clause value)
  (proper value)
  (unless (pair? value) (error "empty ASCENT rule clause"))
  (case (car value)
    ((not)
     (unless (= (length value) 2) (error "ASCENT negation needs one atom"))
     (wire-atom (cadr value) #t))
    ((if)
     (unless (and (= (length value) 3) (list? (cadr value))
                  (list? (caddr value)) (pair? (caddr value))
                  (memq (car (caddr value)) '(< even?))
                  (equal? (cadr value) (cdr (caddr value)))
                  (andmap symbol? (cadr value))
                  (= (length (cadr value)) (if (eq? (car (caddr value)) '<) 2 1)))
       (error "only closed checked ASCENT if operators are supported"))
     (hash ("mode" "where") ("operator" (wire-name (car (caddr value))))
           ("terms" (map wire-term (cadr value)))))
    ((import include guard bind let for if-let match aggregate)
     (error "unsupported executable ASCENT source clause" (car value)))
    (else (wire-atom value))))

(def (read-inert text)
  (unless (and (string? text) (<= (u8vector-length (string->utf8 text)) 65536))
    (error "ASCENT rule source byte bound"))
  (parameterize
      ((current-readtable
        (readtable-sharing-allowed?-set
         (readtable-eval-allowed?-set (current-readtable) #f) #f)))
    (call-with-input-string text
      (lambda (port)
        (let (value (read port))
          (unless (eof-object? (read port)) (error "one inert ASCENT fragment required"))
          (proper value)
          (unless (and (pair? value) (memq (car value) '(ascent ascent-fragment)))
            (error "native ASCENT declarations required; imports and host code are forbidden"))
          (cdr value))))))

(def (column-kind column)
  (unless (and (list? column) (= (length column) 2) (symbol? (car column)))
    (error "explicit typed ASCENT column required"))
  (case (cadr column)
    ((symbol?) 'symbol)
    ((exact-integer? integer?) 'integer)
    ((boolean?) 'boolean)
    (else (error "unsupported ASCENT column predicate" (cadr column)))))

(def (ascent-read-rule-sources texts)
  (unless (and (list? texts) (<= 1 (length texts) 16))
    (error "ASCENT rule source count bound"))
  (let ((declarations (make-hash-table-eq)) (order []) (rules [])
        (heads (make-hash-table-eq)) (seen-rules []) (bytes 0))
    (for-each
     (lambda (text)
       (unless (string? text) (error "ASCENT rule source must be text"))
       (set! bytes (+ bytes (u8vector-length (string->utf8 text))))
       (unless (<= bytes 262144) (error "ASCENT total source byte bound"))
       (for-each
        (lambda (form)
          (proper form)
          (unless (pair? form) (error "empty ASCENT declaration"))
          (if (eq? (car form) 'relation)
            (begin
              (unless (and (= (length form) 3) (symbol? (cadr form))
                           (list? (caddr form)) (<= 0 (length (caddr form)) 16))
                (error "typed ASCENT relation declaration required"))
              (let* ((name (cadr form)) (kinds (map column-kind (caddr form)))
                     (previous (hash-get declarations name)))
                (wire-name name)
                (when (and previous (not (equal? previous kinds)))
                  (error "conflicting ASCENT relation declarations" name))
                (unless previous
                  (hash-put! declarations name kinds)
                  (set! order (cons name order)))))
            (begin
              (unless (and (>= (length form) 3) (eq? (cadr form) '<--))
                (error "native ASCENT head <-- body rule required"))
              (when (member form seen-rules) (error "duplicate ASCENT rule"))
              (set! seen-rules (cons form seen-rules))
              (let* ((head (proper (car form)))
                     (atoms (if (and (pair? head) (symbol? (car head))) (list head) head))
                     (wire-head (map (lambda (atom)
                                       (hash-put! heads (car (proper atom)) #t)
                                       (wire-atom atom)) atoms)))
                (unless (pair? atoms) (error "nonempty ASCENT rule head required"))
                (set! rules (cons (hash ("head" wire-head)
                                        ("body" (map wire-clause (cddr form)))) rules))))))
        (read-inert text))) texts)
    (unless (and (<= 1 (length order) 128) (<= (length rules) 256))
      (error "ASCENT catalog declaration bound"))
    (hash
     ("relations"
      (map (lambda (name)
             (hash ("name" (wire-name name))
                   ("columns" (map (lambda (kind) (hash ("kind" (symbol->string kind))))
                                   (hash-ref declarations name)))
                   ("source" (not (hash-get heads name))))) (reverse order)))
     ("rules" (reverse rules)))))
