;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/table/funs
                 gerbil-ascent-index-key))

(export ascent-index-fixture-program
        ascent-composite-index-fixture-program
        ascent-index-alist-provider)

(def (v name) (gerbil-ascent-variable name))
(def (a name . terms) (gerbil-ascent-atom name terms))

(def (chain-edges length)
  (let loop ((position 0) (rows []))
    (if (= position length)
      (reverse rows)
      (loop (+ position 1)
            (cons (list position (+ position 1)) rows)))))

(def (alist-index-extend index rows columns)
  (let loop ((remaining rows) (current index))
    (if (null? remaining)
      current
      (let* ((row (car remaining))
             (key (gerbil-ascent-index-key row columns))
             (entry (assoc key current)))
        (loop (cdr remaining)
              (cons (cons key (cons row (if entry (cdr entry) [])))
                    (if entry
                      (filter (lambda (item)
                                (not (equal? (car item) key)))
                              current)
                      current)))))))

(def (alist-index-build rows columns)
  (alist-index-extend [] (reverse rows) columns))

(def (ascent-index-alist-provider (on-build (lambda (_columns) (void))))
  (.o (:: @ gerbil-ascent-hash-index-provider)
      (.build-index
       (lambda (rows columns)
         (on-build columns)
         (alist-index-build rows columns)))
      (.extend-index! alist-index-extend)
      (.lookup-index
       (lambda (index key)
         (let (entry (assoc key index))
           (if entry (cdr entry) []))))))

(def (ascent-index-fixture-program (edge-count 50) (index-provider #f))
  (gerbil-ascent-program
   (list (if index-provider
           (gerbil-ascent-relation 'edge 2 (chain-edges edge-count)
                                   index-provider)
           (gerbil-ascent-relation 'edge 2 (chain-edges edge-count)))
         (gerbil-ascent-relation 'two-hop 2 []))
   (list (gerbil-ascent-rule
          (list (a 'two-hop (v 'x) (v 'z)))
          (list (a 'edge (v 'x) (v 'y))
                (a 'edge (v 'y) (v 'z)))))
   (+ edge-count 14) (+ edge-count 14) (* edge-count 3)))

(def (ascent-composite-index-fixture-program (edge-count 50)
                                             (index-provider #f))
  (let (edges
        (append (map (lambda (row) (cons 0 row))
                     (chain-edges edge-count))
                (map (lambda (row)
                       (cons 1 (map (lambda (node) (+ 100 node)) row)))
                     (chain-edges edge-count))))
    (gerbil-ascent-program
     (list (if index-provider
             (gerbil-ascent-relation 'edge 3 edges index-provider)
             (gerbil-ascent-relation 'edge 3 edges))
           (gerbil-ascent-relation 'two-hop 3 []))
     (list (gerbil-ascent-rule
            (list (a 'two-hop (v 'g) (v 'x) (v 'z)))
            (list (a 'edge (v 'g) (v 'x) (v 'y))
                  (a 'edge (v 'g) (v 'y) (v 'z)))))
     (+ (* 2 edge-count) 14) (+ (* 2 edge-count) 14)
     (* 6 edge-count))))
