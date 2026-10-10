;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref)
        :gerbil-ascent/program/index
        :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider gerbil-ascent-curried-index-provider)
        (rename-in (only-in :gerbil-ascent/table/funs gerbil-ascent-index-build)
                   (gerbil-ascent-index-build build-index))
        (rename-in :gerbil-ascent/t/performance/index-entry/reference
                   (gerbil-ascent-make-row-indexes old-make)
                   (row-indexes-rows old-rows) (row-indexes-advance! old-advance!)))
(export index-entry-harness index-entry-atom index-entry-program index-entry-result-rows
        index-entry-provider index-sharing-program)
(def (index-entry-harness old? rows provider)
  (let* ((all (vector rows)) (delta (vector rows))
         (as (vector (length rows))) (ds (vector (length rows)))
         (av (vector 0)) (dv (vector 0))
         (indexes ((if old? old-make gerbil-ascent-make-row-indexes) all delta as ds av dv (vector provider))))
    (vector ((if old? old-rows row-indexes-rows) indexes)
            ((if old? old-advance! row-indexes-advance!) indexes) all delta as ds av dv)))
(def (index-entry-atom columns values (width (+ 1 (apply max columns))))
  (let* ((keys (map (lambda (n) (cons 'literal n)) values))
         (selected (map cons columns keys))
         (terms (map (lambda (column)
                       (let (entry (assoc column selected))
                         (if entry (cdr entry) (cons 'wildcard #f))))
                     (iota width))))
    ;; Lookup keys are a projection; admitted atom terms describe the whole row.
    (vector 0 terms columns terms keys)))
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

;;; Three compatible logical requirements {1}, {0,1}, {0,1,2} select one
;;; physical [1,0,2] chain through the ordinary admitted rule compiler.
(def (index-sharing-program size)
  (let ((a (gerbil-ascent-literal 'a)) (f (gerbil-ascent-literal #f))
        (z (gerbil-ascent-variable 'z)))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'input 3 (map (lambda (n) (list #f 'a n)) (iota size)) gerbil-ascent-curried-index-provider)
           (gerbil-ascent-relation 'out 1 []))
     (list (gerbil-ascent-rule
            (list (gerbil-ascent-atom 'out (list z)))
            (list (gerbil-ascent-atom 'input (list (gerbil-ascent-wildcard) a z))
                  (gerbil-ascent-atom 'input (list f a (gerbil-ascent-wildcard)))
                  (gerbil-ascent-atom 'input (list f a z)))))
     4096 4096 8192)))
