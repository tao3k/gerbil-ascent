;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Evaluation-local equivalence components. The provider owns this private
;;; state; the evaluator creates one instance per declared relation and run.
(import :gerbil-ascent/core/relation-view)
(export gerbil-ascent-eqrel-state gerbil-ascent-eqrel-extension
        gerbil-ascent-eqrel-insert! gerbil-ascent-eqrel-freeze)

;;; A shared component object has explicit member and cached-size fields.
;;; Every member's private index entry points to the same component identity.
(defstruct eqrel-component (members size))

;; : (-> EquivalenceComponents)
(def (gerbil-ascent-eqrel-state)
  (make-hash-table))

;;; Budget preflight must finish before merging components. A rejected source
;;; update must leave the retained session state reusable on the next call.
;; : (-> EquivalenceComponents Rows Rows Row Nat Rows)
(def (gerbil-ascent-eqrel-insert! components row budget)
  (let* ((width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT eqrel requires two or three columns" row)))
         (group (if (= width 3) (car row) #f))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair))
         (right (cadr pair))
         (same-node? (equal? left right))
         (left-key (list width group left))
         (right-key (if same-node? left-key (list width group right)))
         (left-known (hash-get components left-key))
         (right-known (if same-node? left-known
                         (hash-get components right-key)))
         (added []) (needed 0) (blocks []) (cross-left []) (cross-right []))
    (def (emit! from to)
      (set! added
        (cons (if (= width 3)
                (list group from to)
                (list from to))
              added)))
    (def (new-component! node key)
      (let (fresh (make-eqrel-component (list node) 1))
        (hash-put! components key fresh)
        (set! blocks (cons (make-rectangle (if (= width 3) (list group) [])
                                          (list node) (list node)) blocks))
        (emit! node node)
        fresh))
    ;; Count the reflexive facts and cross product before touching components.
    ;; A rejected session append must leave the provider usable for a retry.
    (let* ((new-nodes (+ (if left-known 0 1)
                         (if (or right-known same-node?) 0 1)))
           (left-size (if left-known (eqrel-component-size left-known) 1))
           (right-size (if right-known (eqrel-component-size right-known) 1))
           (count (+ new-nodes
                      (if (or (and left-known right-known
                                   (eq? left-known right-known))
                              same-node?)
                        0
                        (* 2 left-size right-size)))))
      (set! needed count)
      (when (> needed budget)
        (error "ASCENT eqrel output fact budget exceeded")))
    ;; Preflight and commit use the same resolved components. No callbacks
    ;; intervene, so successful admission needs no second hash lookup. An
    ;; already connected edge has no component or row mutation to perform.
    (unless (and left-known (eq? left-known right-known))
      (let* ((left-component
              (or left-known (new-component! left left-key)))
             (right-component
              (if same-node? left-component
                  (or right-known (new-component! right right-key)))))
        (unless (eq? left-component right-component)
          ;; Capture immutable member spines before the weighted merge. Two
          ;; rectangles represent the complete symmetric frontier without pairs.
          (set! cross-left (eqrel-component-members left-component))
          (set! cross-right (eqrel-component-members right-component))
          (let (prefix (if (= width 3) (list group) []))
            (set! blocks (cons (make-rectangle prefix cross-right cross-left)
                              (cons (make-rectangle prefix cross-left cross-right) blocks))))
          (let* ((large (if (>= (eqrel-component-size left-component)
                                (eqrel-component-size right-component))
                          left-component right-component))
                 (small (if (eq? large left-component)
                          right-component left-component))
                 (members (eqrel-component-members small)))
            (for-each
             (lambda (node)
               (hash-put! components (list width group node) large))
             members)
            (eqrel-component-members-set! large
              (append members (eqrel-component-members large)))
            (eqrel-component-size-set! large
              (+ (eqrel-component-size large)
                 (eqrel-component-size small)))))))
    (let ((diagonals (reverse added)) (lefts cross-left) (rights cross-right)
          (prefix (if (= width 3) (list group) [])))
      (gerbil-ascent-view-with-export
        (gerbil-ascent-rectangle-view (reverse blocks) needed (length blocks))
        (lambda ()
          ;; Public ordered export preserves the original interleaved directions.
          ;; This invocation owns its pair spine; the captured cut owns none.
          (let (rows (reverse diagonals))
            (for-each (lambda (from)
              (for-each (lambda (to)
                (set! rows (cons (append prefix (list from to)) rows))
                (set! rows (cons (append prefix (list to from)) rows))) rights)) lefts)
            (reverse rows)))))))

;; Checked public storage dispatch still returns an explicit owned batch.
;; Canonical engine dispatch consumes the same frontier without expanding it.
(def (gerbil-ascent-eqrel-extension components _all _pending row budget)
  (gerbil-ascent-view-rows (gerbil-ascent-eqrel-insert! components row budget)))

(def (gerbil-ascent-eqrel-freeze components (indexed? #t))
  (let ((seen (make-hash-table-eq)) (blocks []) (count 0))
    (hash-for-each (lambda (key component)
      (unless (hash-get seen component)
        (hash-put! seen component #t)
        (let ((members (eqrel-component-members component))
              (size (eqrel-component-size component)))
          (set! blocks (cons (make-rectangle
            (if (= (car key) 3) (list (cadr key)) []) members members) blocks))
          (set! count (+ count (* size size)))))) components)
    (gerbil-ascent-rectangle-view (reverse blocks) count (length blocks) indexed?)))
