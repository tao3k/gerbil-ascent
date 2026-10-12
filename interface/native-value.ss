;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil/runtime/hash make-hash-table-eq)
        (only-in :std/hash/misc hash-key?))
(export ascent-value-graph ascent-value-input)

;; Encoding is independent of execution. Every node retains its actual native
;; value, including opaque values and cycles; references belong to one result.
(def (ascent-value-graph root retained)
  (let ((seen (make-hash-table-eq)) (nodes []) (serial (hash-length retained)))
    (def (walk value)
      (cond
       ((eq? value #!void) (hash ("type" "void")))
       ((null? value) (hash ("type" "null")))
       ((boolean? value) (hash ("type" "boolean") ("value" value)))
       ((number? value) (hash ("type" "number") ("value" (number->string value))))
       ((char? value) (hash ("type" "character") ("value" (char->integer value))))
       (else
        (let (old (hash-get seen value))
          (if old (hash ("ref" old))
            (begin
              (set! serial (+ serial 1))
              (when (> serial 65536) (error "native graph transport bound; native result remains retained"))
              (let (id serial)
                (hash-put! seen value id)
                (hash-put! retained id value)
                (let (node
                       (cond
                        ((symbol? value) (hash ("id" id) ("type" "symbol")
                                              ("value" (symbol->string value))
                                              ("interned" (interned-symbol? value))))
                        ((string? value) (hash ("id" id) ("type" "string") ("value" value)))
                        ((pair? value) (hash ("id" id) ("type" "pair")
                                            ("car" (walk (car value))) ("cdr" (walk (cdr value)))))
                        ((vector? value) (hash ("id" id) ("type" "vector")
                                              ("items" (map walk (vector->list value)))))
                        ((u8vector? value) (hash ("id" id) ("type" "u8vector")
                                                ("items" (u8vector->list value))))
                        ((hash-table? value)
                         (let (entries [])
                           (hash-for-each (lambda (key item)
                             (set! entries (cons (list (walk key) (walk item)) entries))) value)
                           (hash ("id" id) ("type" "hash-table") ("entries" (reverse entries)))))
                        (else (hash ("id" id) ("type" "opaque")
                                    ("encoding" "native-reference-only")))))
                  (set! nodes (cons node nodes)))
                (hash ("ref" id)))))))))
    (let (encoded (walk root))
      (hash ("format" "native-value-graph.v1") ("root" encoded) ("nodes" (reverse nodes))))))

;; Native predicates and contracts validate decoded inputs, not Python.
;; Compound references are resolved by the owning session, never globally.
(def (ascent-value-input value resolve)
  (if (and (hash-table? value) (hash-key? value "type"))
    (let ((kind (hash-ref value "type")) (item (hash-ref value "value" #f)))
      (cond
       ((equal? kind "symbol") (unless (string? item) (error "invalid symbol")) (string->symbol item))
       ((equal? kind "number") (or (and (string? item) (string->number item)) (error "invalid number")))
       ((equal? kind "character") (unless (and (exact-integer? item) (<= 0 item #x10ffff)) (error "invalid character")) (integer->char item))
       ((equal? kind "vector") (unless (list? item) (error "invalid vector"))
        (list->vector (map (lambda (v) (ascent-value-input v resolve)) item)))
       ((equal? kind "u8vector") (unless (and (list? item) (andmap (lambda (v) (and (exact-integer? v) (<= 0 v 255))) item)) (error "invalid bytes")) (list->u8vector item))
       ((equal? kind "pair")
        (cons (ascent-value-input (hash-ref value "car") resolve)
              (ascent-value-input (hash-ref value "cdr") resolve)))
       ((equal? kind "reference") (resolve value))
       (else (error "unsupported native input encoding"))))
    (if (list? value) (map (lambda (v) (ascent-value-input v resolve)) value) value)))
