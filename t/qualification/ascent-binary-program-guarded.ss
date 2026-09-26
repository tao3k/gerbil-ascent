;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Test-only positive binary rule fixture. MRR compares these Scheme rows
;;; with the same guarded copy/join program evaluated directly by Rust Ascent.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/ascent-binary-program
                 gerbil-ascent-binary-relation
                 gerbil-ascent-binary-copy-rule
                 gerbil-ascent-binary-filter-rule
                 gerbil-ascent-binary-join-rule
                 gerbil-ascent-evaluate-binary-program))

(export main)

(def (parse-node node width)
  (unless (and (exact-integer? node) (<= 0 node) (< node width))
    (error "invalid ASCENT guarded fixture node" node))
  node)

(def (source-pairs nodes width)
  (let loop ((remaining nodes) (pairs []))
    (if (null? remaining)
      (reverse pairs)
      (loop (cddr remaining)
            (cons (+ (* (car remaining) width) (cadr remaining))
                  pairs)))))

(def (main . args)
  (unless (null? args)
    (error "ASCENT guarded fixture reads one numeric edge list from stdin"))
  (let* ((request (read))
         (request-check
          (unless (and (list? request) (>= (length request) 3)
                       (odd? (length request)))
            (error "ASCENT guarded fixture expects (RADIX FROM TO ...)")))
         (width (car request))
         (radix-check
          (unless (and (exact-integer? width) (> width 1))
            (error "invalid ASCENT guarded fixture radix")))
         (nodes (map (lambda (value) (parse-node value width))
                     (cdr request)))
         (empty (.call UIntTrieSet .<-list []))
         (result
          (gerbil-ascent-evaluate-binary-program
           (.o (radix width)
               (relations
                (list (gerbil-ascent-binary-relation
                       'edge (.call UIntTrieSet .<-list
                                    (source-pairs nodes width)))
                      (gerbil-ascent-binary-relation 'selected empty)
                      (gerbil-ascent-binary-relation 'copied empty)
                      (gerbil-ascent-binary-relation 'twohop empty)))
               (rules
                (list (gerbil-ascent-binary-filter-rule
                       'selected 'edge
                       (lambda (from _to) (even? from)))
                      (gerbil-ascent-binary-copy-rule
                       'copied 'selected)
                      (gerbil-ascent-binary-join-rule
                       'twohop 'selected 'edge)))
               (max-input-facts 4096)
               (max-derived-pairs 4096)
               (max-output-pairs 8192)))))
    (unless (eq? (.ref result 'evaluation-path) 'semi-naive)
      (error "ASCENT guarded fixture selected unexpected evaluation path"))
    (for-each
     (lambda (name)
       (for-each
        (lambda (pair)
          (display name)
          (display "\t")
          (display (quotient pair width))
          (display "\t")
          (display (modulo pair width))
          (newline))
        ((.ref result 'pair-list-of) name)))
     '(selected copied twohop))))
