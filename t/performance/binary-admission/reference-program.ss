;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Finite positive binary rules. Relations, rules, and results are POO
;;; objects; evaluation publishes canonical pair lists and can materialize the
;;; official persistent set on demand. Private adjacency indexes serve the
;;; bounded semi-naive hot path.

(import (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/trie UIntTrieSet)
        (only-in :clan/poo/support/base until)
        (only-in :std/list/list filter)
        (only-in :gerbil-ascent/t/performance/binary-admission/reference-expression
                 binary-admission-reference-closure-bounded))

(export binary-admission-reference-binary-relation
        binary-admission-reference-binary-copy-rule
        binary-admission-reference-binary-filter-rule
        binary-admission-reference-binary-join-rule
        binary-admission-reference-evaluate-binary-program)

(def (binary-admission-reference-binary-relation relation-name source-set)
  (.o (name relation-name) (pairs source-set)))

(def (binary-admission-reference-binary-copy-rule head-name body-name)
  (.o (kind 'copy) (head head-name) (left body-name)))

;;; The guard is a pure Scheme predicate over decoded (from, to) endpoints.
(def (binary-admission-reference-binary-filter-rule head-name body-name guard)
  (unless (procedure? guard)
    (error "ASCENT binary filter requires a predicate"))
  (.o (kind 'filter) (head head-name) (left body-name)
      (predicate guard)))

(def (binary-admission-reference-binary-join-rule head-name left-name right-name)
  (.o (kind 'join) (head head-name)
      (left left-name) (right right-name)))

;;; The selected Ascent copy plus recursive transitive rule has an existing
;;; bounded Scheme closure. Recognize that rule shape independently of order.
(def (transitive-pattern rules all position-of)
  (and (= (length rules) 2)
       (let* ((copies (filter (lambda (rule)
                                (eq? (.ref rule 'kind) 'copy)) rules))
              (joins (filter (lambda (rule)
                               (eq? (.ref rule 'kind) 'join)) rules)))
         (and (= (length copies) 1) (= (length joins) 1)
              (let* ((copy-rule (car copies))
                     (join-rule (car joins))
                     (head-name (.ref copy-rule 'head))
                     (source-name (.ref copy-rule 'left)))
                (and (eq? head-name (.ref join-rule 'head))
                     (eq? head-name (.ref join-rule 'left))
                     (eq? source-name (.ref join-rule 'right))
                     (not (eq? head-name source-name))
                     (null? (vector-ref all (position-of head-name)))
                     (.o (source-index (position-of source-name))
                         (head-index (position-of head-name)))))))))

;;; Dense arrays handle bounded small domains; sparse hash indexes avoid
;;; allocating a quadratic domain when radix is large. Both paths publish
;;; the same canonical relation rows and POO result interface.
;; binary-admission-reference-evaluate-binary-program
;;   : (-> BinaryProgram BinaryResult)
;;   | doc m%
;;       Evaluate finite copy, filter, and join rules to their fixed point.
;;
;;       # Examples
;;
;;       ```scheme
;;       (binary-admission-reference-evaluate-binary-program program)
;;       ;; => a result exposing relation names and pair snapshots
;;       ```
;;     %
(def (binary-admission-reference-evaluate-binary-program program)
  (let* ((width (.ref program 'radix))
         (sources (.ref program 'relations))
         (rules (.ref program 'rules))
         (input-limit (.ref program 'max-input-facts))
         (limit (.ref program 'max-derived-pairs))
         (output-limit (.ref program 'max-output-pairs)))
    (unless (and (exact-integer? width) (> width 1)
                 (exact-integer? input-limit) (> input-limit 0)
                 (exact-integer? limit) (> limit 0)
                 (exact-integer? output-limit) (> output-limit 0)
                 (list? sources) (list? rules))
      (error "invalid ASCENT binary program bounds or declarations"))
    ;; These mutable arrays are private to one evaluation. The public boundary
    ;; remains immutable UIntTrieSet snapshots and POO relation objects.
    (let* ((count (length sources))
           (source-vector (list->vector sources))
           (names (make-vector count #f))
           (positions (make-hash-table))
           (all (make-vector count []))
           (delta (make-vector count []))
           (all-index (make-vector count #f))
           (delta-index (make-vector count #f))
           (seen (make-vector count #f))
           (pending-epochs (make-vector count #f))
           (indexed-rights (make-hash-table))
           (derived-heads (make-hash-table))
           (dense? (<= width 512))
           (source-count 0)
           (derived-count 0)
           (position-counter 0))
      ;;; Intentional raw data record: the adjacency index is evaluation-local
      ;;; mutable storage, while public relations remain validated POO values.
      (def (new-index)
        (if dense? (make-vector width []) (make-hash-table)))
      (def (index-targets index node)
        (if dense? (vector-ref index node) (or (hash-get index node) [])))
      (def (index-add! index pair)
        (let ((from (quotient pair width)) (to (modulo pair width)))
          (if dense?
            (vector-set! index from (cons to (vector-ref index from)))
            (hash-put! index from (cons to (index-targets index from))))))
      ;;; Intentional raw data record: one membership bit per possible pair
      ;;; avoids object allocation in the semi-naive inner loop.
      (def (new-seen)
        (if dense? (make-u8vector (* width width) 0) (make-hash-table)))
      (def (seen? storage pair)
        (if dense? (= (u8vector-ref storage pair) 1)
            (hash-get storage pair)))
      (def (mark-seen! storage pair)
        (if dense? (u8vector-set! storage pair 1)
            (hash-put! storage pair #t)))
      ;;; Intentional raw data record: epochs deduplicate pending pairs without
      ;;; clearing a full dense table between fixed-point rounds.
      (def (new-pending-epochs)
        (if dense? (make-vector (* width width) 0) (make-hash-table)))
      (def (pending-epoch storage pair)
        (if dense? (vector-ref storage pair)
            (hash-get storage pair)))
      (def (mark-pending! storage pair epoch)
        (if dense? (vector-set! storage pair epoch)
            (hash-put! storage pair epoch)))
      (for-each
       (lambda (rule)
         (hash-put! derived-heads (.ref rule 'head) #t)
         (when (eq? (.ref rule 'kind) 'join)
           (hash-put! indexed-rights (.ref rule 'right) #t)))
       rules)
      (for-each
       (lambda (relation)
         (let* ((name (.ref relation 'name))
                (pairs (.ref relation 'pairs))
                (position position-counter))
           (unless (and (symbol? name) (not (hash-get positions name)))
             (error "invalid or duplicate ASCENT relation" name))
           (.call UIntTrieSet .foldl
                  (lambda (pair _)
                    (unless (and (exact-integer? pair) (<= 0 pair)
                                 (< pair (* width width)))
                      (error "invalid ASCENT binary pair" pair))
                    (set! source-count (+ source-count 1))
                    (when (> source-count input-limit)
                      (error "ASCENT input fact budget exceeded"
                             source-count input-limit))
                    (when (> source-count output-limit)
                      (error "ASCENT output pair budget exceeded"
                             source-count output-limit))
                    (vector-set! all position
                                 (cons pair (vector-ref all position)))
                    (void))
                  (void) pairs)
           (vector-set! names position name)
           (hash-put! positions name (+ position 1))
           (set! position-counter (+ position-counter 1))
           (vector-set! delta position (vector-ref all position))))
       sources)
      (def (position-of name)
        (let (slot (hash-get positions name))
          (unless slot (error "unknown ASCENT relation" name))
          (- slot 1)))
      (for-each
       (lambda (rule)
         (let (kind (.ref rule 'kind))
           (unless (memq kind '(copy filter join))
             (error "invalid ASCENT binary rule" kind))
           (position-of (.ref rule 'head))
           (position-of (.ref rule 'left))
           (when (eq? kind 'filter)
             (unless (procedure? (.ref rule 'predicate))
               (error "invalid ASCENT binary filter predicate")))
           (when (eq? kind 'join)
             (position-of (.ref rule 'right)))))
       rules)
      (def (publish-result results path-name)
        ;; Private records pair a row copy with its persistent set. Validate the
        ;; copy on every demand: public lists are mutable, even though native
        ;; UIntTrieSet snapshots can safely be shared.
        (let (snapshots (make-vector count #f))
          (.o (relation-names (vector->list names))
              (evaluation-path path-name)
              (pair-list-of
               (lambda (name)
                 (vector-ref results (position-of name))))
              (pairs-of
               (lambda (name)
                 (let* ((i (position-of name)) (rows (vector-ref results i))
                        (cached (vector-ref snapshots i)))
                   (unless (or cached (hash-get derived-heads name))
                     ;; Unchanged inputs already own the requested native set.
                     ;; Compare with private captured rows, including mutations
                     ;; made before the first set demand.
                     (set! cached (vector (reverse (vector-ref all i))
                                          (.ref (vector-ref source-vector i) 'pairs)))
                     (vector-set! snapshots i cached))
                   (if (and cached (equal? rows (vector-ref cached 0)))
                     (vector-ref cached 1)
                     (let (value (.call UIntTrieSet .<-list rows))
                       (vector-set! snapshots i (vector (append rows []) value))
                       value))))))))
      ;; Validation captures source rows once. Only the general evaluator needs
      ;; membership, pending epochs, and join indexes; build those after dispatch.
      (def (initialize-general-state!)
        (let initialize ((i 0))
          (when (< i count)
            (let* ((name (vector-ref names i))
                   (rows (vector-ref all i))
                   (links (and (hash-get indexed-rights name) (new-index)))
                   (present (and (hash-get derived-heads name) (new-seen))))
              ;; Replay indexed sources in the original fold order. Neighbor
              ;; order can affect filter callback traces in subsequent rounds.
              (when (or links present)
                (for-each
                 (lambda (pair)
                   (when present (mark-seen! present pair))
                   (when links (index-add! links pair)))
                 (if links (reverse rows) rows)))
              (vector-set! seen i present)
              (when present (vector-set! pending-epochs i (new-pending-epochs)))
              (vector-set! all-index i links)
              (vector-set! delta-index i links))
            (initialize (+ i 1)))))
      (let (pattern (and dense? (transitive-pattern rules all position-of)))
        (if pattern
          (let* ((source-position (.ref pattern 'source-index))
                 (head-position (.ref pattern 'head-index))
                 (source-set
                  (.ref (vector-ref source-vector source-position) 'pairs))
                 (allowance (min limit (- output-limit source-count)))
                 (closure-pairs
                  (.ref (binary-admission-reference-closure-bounded
                         source-set width allowance) 'pairs))
                 (results (make-vector count #f)))
            (let publish-sources ((i 0))
              (when (< i count)
                (vector-set! results i
                             (reverse (vector-ref all i)))
                (publish-sources (+ i 1))))
            (vector-set! results head-position closure-pairs)
            (publish-result results 'transitive-closure))
          (let (instructions
                ;; Evaluation-local positional instructions retain declaration
                ;; order. Resolve immutable rule slots once, outside the rounds.
                (map (lambda (rule)
                       (let (kind (.ref rule 'kind))
                         (vector kind (position-of (.ref rule 'head))
                                 (position-of (.ref rule 'left))
                                 (and (eq? kind 'join) (position-of (.ref rule 'right)))
                                 (and (eq? kind 'filter) (.ref rule 'predicate)))))
                     rules))
            (initialize-general-state!)
            (let ((active? #t) (epoch 0))
              (until (not active?)
                (let ((pending (make-vector count []))
                      (next (make-vector count []))
                      (next-index (make-vector count #f))
                      (pending-count 0))
                  (set! epoch (+ epoch 1))
                  (def (emit! head pair)
                    (unless (or (seen? (vector-ref seen head) pair)
                                (eqv? (pending-epoch
                                       (vector-ref pending-epochs head) pair)
                                      epoch))
                      (mark-pending! (vector-ref pending-epochs head) pair epoch)
                      (set! pending-count (+ pending-count 1))
                      (when (> (+ derived-count pending-count) limit)
                        (error "ASCENT derived pair budget exceeded" limit))
                      (when (> (+ source-count derived-count pending-count)
                               output-limit)
                        (error "ASCENT output pair budget exceeded" output-limit))
                      (vector-set! pending head
                                   (cons pair (vector-ref pending head)))))
                  (def (compose! head left-pairs right-index)
                    (for-each
                     (lambda (pair)
                       (let ((origin (quotient pair width))
                             (middle (modulo pair width)))
                         (for-each
                          (lambda (target)
                            (emit! head (+ (* origin width) target)))
                          (index-targets right-index middle))))
                     left-pairs))
                  (for-each
                   (lambda (rule)
                     (let ((kind (vector-ref rule 0))
                           (head (vector-ref rule 1))
                           (left (vector-ref rule 2)))
                       (case kind
                         ((copy)
                          (for-each (lambda (pair) (emit! head pair))
                                    (vector-ref delta left)))
                         ((filter)
                          (for-each
                           (lambda (pair) (emit! head pair))
                           (filter
                            (lambda (pair)
                              (let (accepted?
                                    ((vector-ref rule 4)
                                     (quotient pair width)
                                     (modulo pair width)))
                                (unless (boolean? accepted?)
                                  (error "ASCENT binary filter must return boolean"))
                                accepted?))
                            (vector-ref delta left))))
                         ((join)
                          (let (right (vector-ref rule 3))
                            (unless (null? (vector-ref delta left))
                              (compose! head (vector-ref delta left)
                                        (vector-ref all-index right)))
                            (unless (null? (vector-ref delta right))
                              (compose! head (vector-ref all left)
                                        (vector-ref delta-index right))))))))
                   instructions)
                  (set! active? #f)
                  (let commit ((i 0))
                    (when (< i count)
                      ;; Only relations with newly committed rows need an index
                      ;; for the next delta. Unchanged right inputs retain their
                      ;; all-index and have an empty delta with no delta-index.
                      (when (and (pair? (vector-ref pending i))
                                 (vector-ref all-index i))
                        (vector-set! next-index i (new-index)))
                      (for-each
                       (lambda (pair)
                         (mark-seen! (vector-ref seen i) pair)
                         (set! active? #t)
                         (set! derived-count (+ derived-count 1))
                         (vector-set! all i (cons pair (vector-ref all i)))
                         (vector-set! next i (cons pair (vector-ref next i)))
                         (when (vector-ref all-index i)
                           (index-add! (vector-ref all-index i) pair)
                           (index-add! (vector-ref next-index i) pair)))
                       (vector-ref pending i))
                      (commit (+ i 1))))
                  (set! delta next)
                  (set! delta-index next-index))))
            (let (results (make-vector count #f))
              (let publish ((i 0))
                (when (< i count)
                  (vector-set! results i
                               (list-sort < (append (vector-ref all i) [])))
                  (publish (+ i 1))))
              (publish-result results 'semi-naive))))))))
