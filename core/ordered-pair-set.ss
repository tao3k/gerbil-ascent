;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .ref .call)
        (only-in :clan/poo/support/base until)
        (only-in :clan/poo/trie UIntTrieSet))
(export gerbil-ascent-ordered-pair-set)

;; : (-> EncodedRows Boolean)
(def (ordered-uints? rows)
  (and (list? rows)
       (let (previous -1)
         (andmap (lambda (key)
                   (and (exact-integer? key) (> key previous)
                        (begin (set! previous key) #t))) rows))))

;; gerbil-ascent-ordered-pair-set
;; : (forall (p) (-> (EncodedRows p) (UIntTrieSet p)))
;; : (-> EncodedRows UIntTrieSet)
;; | doc m%
;;     Publish sorted unique unsigned keys using the native Trie Table constructor
;;     contract. Each Patricia branch is built once. Other input shapes retain
;;     the original Set admission, duplicate and error behavior.
;;     Encoded keys and Patricia bit heights retain generic exact arithmetic,
;;     including keys above 2^64. Binary search indexes only the owned vector;
;;     no machine-word assumption narrows the public unsigned key domain.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-ordered-pair-set '(10 11 19))
;;     ;; => the same persistent UIntTrieSet as .<-list
;;     ```
;;   %
(def (gerbil-ascent-ordered-pair-set rows)
  (if (not (ordered-uints? rows))
    (.call UIntTrieSet .<-list rows)
    (if (null? rows)
      (.ref UIntTrieSet '.empty)
      (let* ((keys (list->vector rows))
             (table (.ref UIntTrieSet 'Table))
             (leaf (.ref table '.make-leaf))
             (branch (.ref table '.branch))
             (skip (.ref table '.make-skip)))
        (def (split lo hi bit)
          ;; Narrow an owned half-open index interval to its bit partition.
          ;; This monotone range driver does not construct an intermediate list.
          (let ((left lo) (right hi))
            (until (= left right)
              (let (middle (quotient (+ left right) 2))
                (if (bit-set? bit (vector-ref keys middle))
                  (set! right middle)
                  (set! left (+ middle 1)))))
            left))
        (def (build lo hi height)
          (let (first (vector-ref keys lo))
            (if (= (+ lo 1) hi)
              (leaf height first (void))
              (let* ((last (vector-ref keys (- hi 1)))
                     (bit (- (integer-length (bitwise-xor first last)) 1))
                     (middle (split lo hi bit))
                     (joined (branch bit (build lo middle (- bit 1))
                                         (build middle hi (- bit 1)))))
                (if (= bit height) joined
                  (skip height (- height bit 1)
                        (arithmetic-shift first (- (+ bit 1))) joined))))))
        (build 0 (vector-length keys)
               (- (integer-length (vector-ref keys (- (vector-length keys) 1))) 1))))))
