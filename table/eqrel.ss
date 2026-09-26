;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Evaluation-local equivalence components. The provider owns this private
;;; state; the evaluator creates one instance per declared relation and run.
(export gerbil-ascent-eqrel-state gerbil-ascent-eqrel-extension)

(def (gerbil-ascent-eqrel-state)
  (make-hash-table))

(def (gerbil-ascent-eqrel-extension components _all _pending row budget)
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT eqrel requires two or three columns" row)))
         (group (if (= width 3) (car row) #f))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair))
         (right (cadr pair))
         (added [])
         (added-count 0))
    (def (emit! from to)
      (set! added-count (+ added-count 1))
      (when (> added-count budget)
        (error "ASCENT eqrel output fact budget exceeded"))
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
