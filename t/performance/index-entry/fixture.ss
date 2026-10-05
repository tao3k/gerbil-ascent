;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref)
        :gerbil-ascent/program/index
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (rename-in (only-in :gerbil-ascent/table/funs gerbil-ascent-index-build)
                   (gerbil-ascent-index-build build-index))
        (rename-in :gerbil-ascent/t/performance/index-entry/reference
                   (gerbil-ascent-make-row-indexes old-make)
                   (row-indexes-rows old-rows) (row-indexes-advance! old-advance!)))
(export index-entry-harness index-entry-atom index-entry-program index-entry-result-rows
        index-entry-provider)
(def (index-entry-harness old? rows provider)
  (let* ((all (vector rows)) (delta (vector rows))
         (as (vector (length rows))) (ds (vector (length rows)))
         (av (vector 0)) (dv (vector 0))
         (indexes ((if old? old-make gerbil-ascent-make-row-indexes) all delta as ds av dv (vector provider))))
    (vector ((if old? old-rows row-indexes-rows) indexes)
            ((if old? old-advance! row-indexes-advance!) indexes) all delta as ds av dv)))
(def (index-entry-atom columns values)
  (let (terms (map (lambda (n) (cons 'literal n)) values))
    (vector 0 terms columns terms terms)))
(def (index-entry-provider emit (reject (lambda (_) #f)))
  (.o (:: @ gerbil-ascent-hash-index-provider)
      (.build-index
       (lambda (rows columns)
         (emit (list 'build columns rows))
         (when (reject 'build) (error "planned build failure"))
         (vector (build-index rows columns) rows)))
      (.extend-index!
       (lambda (index rows columns)
         (emit (list 'extend columns rows))
         (when (reject 'extend) (error "planned extend failure"))
         ;; Return a new physical value, never mutate the supplied index.
         (let (all (append (reverse rows) (vector-ref index 1)))
           (vector (build-index all columns) all))))
      (.lookup-index
       (lambda (index key)
         (emit (list 'lookup key))
         (or (hash-get (vector-ref index 0) key) [])))))
(def (index-entry-program size width rules)
  (let* ((names (map (lambda (n) (string->symbol (string-append "x" (number->string n)))) (iota width)))
         (variables (map gerbil-ascent-variable names))
         (rows (map (lambda (n) (map (lambda (c) (+ n c)) (iota width))) (iota size))))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input width rows)
           (gerbil-ascent-relation 'out 1 []))
     (map (lambda (_)
            (gerbil-ascent-rule
             (list (gerbil-ascent-atom 'out (list (car variables))))
             (list (gerbil-ascent-atom 'input variables)
                   (gerbil-ascent-atom 'input variables)))) (iota rules))
     4096 4096 8192)))
(def (index-entry-result-rows result) ((.ref result 'rows-of) 'out))
