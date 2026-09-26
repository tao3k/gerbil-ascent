;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Test-only process adapter. MRR supplies the exact source edges and compares
;;; the resulting Scheme pairs against its independently evaluated Ascent rule.
;;; (generic RADIX ...) routes the same rule through an intermediate relation
;;; so the composable semi-naive evaluator is exercised independently.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :gerbil-ascent/ascent-binary-program
                 gerbil-ascent-binary-relation
                 gerbil-ascent-binary-copy-rule
                 gerbil-ascent-binary-join-rule
                 gerbil-ascent-evaluate-binary-program))

(export main)

(def (parse-node node width)
  (unless (and (exact-integer? node) (<= 0 node) (< node width))
    (error "invalid ASCENT fixture node" node))
  node)

(def (main . args)
  (unless (null? args)
    (error "ASCENT fixture reads one numeric edge list from stdin"))
  (let* ((raw-request (read))
         (generic? (and (pair? raw-request)
                        (eq? (car raw-request) 'generic)))
         (request (if generic? (cdr raw-request) raw-request))
         (request-check
          (unless (and (list? request)
                       (>= (length request) 3)
                       (odd? (length request)))
            (error "ASCENT fixture expects (RADIX FROM TO [FROM TO ...])")))
         (width (car request))
         (radix-check
          (unless (and (exact-integer? width) (> width 1))
            (error "invalid ASCENT fixture radix")))
         (nodes (map (lambda (value) (parse-node value width))
                     (cdr request)))
         (edges
          (let loop ((remaining nodes) (pairs []))
            (if (null? remaining)
              (reverse pairs)
              (loop (cddr remaining)
                    (cons (+ (* (car remaining) width) (cadr remaining))
                          pairs)))))
         (edge-set (.call UIntTrieSet .<-list edges))
         (result
          (gerbil-ascent-evaluate-binary-program
           (.o (radix width)
               (relations
                (append
                 (list (gerbil-ascent-binary-relation 'edge edge-set))
                 (if generic?
                   (list (gerbil-ascent-binary-relation
                          'staged (.call UIntTrieSet .<-list [])))
                   [])
                 (list (gerbil-ascent-binary-relation
                        'reach (.call UIntTrieSet .<-list [])))))
               (rules
                (if generic?
                  (list (gerbil-ascent-binary-copy-rule 'staged 'edge)
                        (gerbil-ascent-binary-copy-rule 'reach 'staged)
                        (gerbil-ascent-binary-join-rule
                         'reach 'reach 'edge))
                  (list (gerbil-ascent-binary-copy-rule 'reach 'edge)
                        (gerbil-ascent-binary-join-rule
                         'reach 'reach 'edge))))
               (max-input-facts 4096)
               (max-derived-pairs 4096)
               (max-output-pairs 8192)))))
    (unless (eq? (.ref result 'evaluation-path)
                 (if generic? 'semi-naive 'transitive-closure))
      (error "ASCENT fixture selected unexpected evaluation path"))
    (for-each
     (lambda (pair)
       (display (quotient pair width))
       (display "\t")
       (display (modulo pair width))
       (newline))
     ((.ref result 'pair-list-of) 'reach))))
