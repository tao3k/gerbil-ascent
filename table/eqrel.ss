;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Evaluation-local equivalence components. The provider owns this private
;;; state; the evaluator creates one instance per declared relation and run.
(export gerbil-ascent-eqrel-state gerbil-ascent-eqrel-extension)

;; : (-> EquivalenceComponents)
(def (gerbil-ascent-eqrel-state)
  (make-hash-table))

;;; Budget preflight must finish before merging components. A rejected source
;;; update must leave the retained session state reusable on the next call.
;; : (-> EquivalenceComponents Rows Rows Row Nat Rows)
(def (gerbil-ascent-eqrel-extension components _all _pending row budget)
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT eqrel requires two or three columns" row)))
         (group (if (= width 3) (car row) #f))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair))
         (right (cadr pair))
         (added []))
    (def (emit! from to)
      (set! added
        (cons (if (= width 3)
                (list group from to)
                (list from to))
              added)))
    (def (component-of node)
      (let* ((key (cons group node))
             (known (hash-get components key)))
        (or known
            (let (fresh (vector (list node) 1))
              (hash-put! components key fresh)
              (emit! node node)
              fresh))))
    ;; Count the reflexive facts and cross product before touching components.
    ;; A rejected session append must leave the provider usable for a retry.
    (let* ((left-known (hash-get components (cons group left)))
           (right-known (hash-get components (cons group right)))
           (new-nodes (+ (if left-known 0 1)
                         (if (or right-known (equal? left right)) 0 1)))
           (left-size (if left-known (vector-ref left-known 1) 1))
           (right-size (if right-known (vector-ref right-known 1) 1))
           (needed (+ new-nodes
                      (if (or (and left-known right-known
                                   (eq? left-known right-known))
                              (equal? left right))
                        0
                        (* 2 left-size right-size)))))
      (when (> needed budget)
        (error "ASCENT eqrel output fact budget exceeded")))
    (let ((left-component (component-of left))
          (right-component (component-of right)))
      (unless (eq? left-component right-component)
        (for-each
         (lambda (from)
           (for-each
            (lambda (to)
              (emit! from to)
              (emit! to from))
            (vector-ref right-component 0)))
         (vector-ref left-component 0))
        (let* ((large (if (>= (vector-ref left-component 1)
                              (vector-ref right-component 1))
                        left-component right-component))
               (small (if (eq? large left-component)
                        right-component left-component))
               (members (vector-ref small 0)))
          (for-each
           (lambda (node)
             (hash-put! components (cons group node) large))
           members)
          (vector-set! large 0 (append members (vector-ref large 0)))
          (vector-set! large 1 (+ (vector-ref large 1)
                                  (vector-ref small 1))))))
    (reverse added)))
