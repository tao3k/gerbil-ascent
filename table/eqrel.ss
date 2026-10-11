;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Evaluation-local weighted components; published cuts borrow immutable member
;;; spines, never mutable component records or the owner's membership table.
(import :gerbil-ascent/core/relation-view)
(export gerbil-ascent-eqrel-state gerbil-ascent-eqrel-extension
        gerbil-ascent-eqrel-state? gerbil-ascent-eqrel-insert!
        gerbil-ascent-eqrel-freeze gerbil-ascent-eqrel-publish! gerbil-ascent-eqrel-observation
        gerbil-ascent-eqrel-replay-insert!)
(defstruct eqrel-component (members size))
(defstruct eqrel-cut (count view))
(defstruct eqrel-state (components count published origin))
(def gerbil-ascent-eqrel-state? eqrel-state?)
(def (empty-cut)
  (make-eqrel-cut 0 (gerbil-ascent-explicit-view [] 0)))
(def (gerbil-ascent-eqrel-state)
  (let (empty (empty-cut)) (make-eqrel-state (make-hash-table) 0 empty empty)))

(def (member-key width group node) (list width group node))
(defstruct coordinate-key (bound? value coherent?) final: #t)
;;; A coordinate admits one value or no values. Bind false normally; repeated
;;; constraints must agree before selecting any owned member.
;; : (-> Natural Columns Key CoordinateKey)
(def (compile-coordinate-key coordinate columns key)
  (let ((bound? #f) (value #f) (coherent? #t))
    (for-each (lambda (column selected)
      (when (= column coordinate)
        (if bound? (set! coherent? (and coherent? (equal? value selected)))
          (begin (set! bound? #t) (set! value selected))))) columns key)
    (make-coordinate-key bound? value coherent?)))
;; : (-> CoordinateKey Value Boolean)
(def (coordinate-accepts? constraint value)
  (using (constraint :- coordinate-key)
    (and constraint.coherent? (or (not constraint.bound?) (equal? constraint.value value)))))
;; : (-> CoordinateKey UniqueMembers UniqueMembers)
(def (coordinate-members constraint members)
  (using (constraint :- coordinate-key)
    (cond ((not constraint.coherent?) [])
          ((not constraint.bound?) members)
          (else (let (found (member constraint.value members))
                  (if found (list (car found)) []))))))
;; : (-> CoordinateKey CoordinateKey UniqueMembers UniqueMembers PairWriter Void)
;;; Select each orientation before traversal. Their ordered union keeps
;;; interleaved forward/reverse output when both orientations are eligible.
(def (visit-selected-members! left-key right-key lefts rights emit)
  (let* ((forward (coordinate-members right-key rights))
         (backward (coordinate-members left-key rights))
         (both (if (or (eq? forward rights) (eq? backward rights)) rights
                 (filter (lambda (b) (or (coordinate-accepts? right-key b)
                                         (coordinate-accepts? left-key b))) rights))))
    (for-each (lambda (a)
      (let ((forward? (coordinate-accepts? left-key a))
            (backward? (coordinate-accepts? right-key a)))
        (for-each (lambda (b)
          (when (and forward? (coordinate-accepts? right-key b)) (emit a b))
          (when (and backward? (coordinate-accepts? left-key b)) (emit b a)))
          (cond ((and forward? backward?) both) (forward? forward) (backward? backward) (else []))))) lefts)))
;;; Frontier order matches the eager algorithm: fresh diagonals, then each
;;; left/right cross pair followed immediately by its symmetric counterpart.
;; : (-> Prefix UniqueMembers UniqueMembers UniqueMembers RowWriter Void)
(def (write-injection! prefix diagonals lefts rights consume)
  ;; Admission permits only two columns or one group plus two coordinates.
  ;; Select the fixed row constructor once, outside the Cartesian writer.
  (def emit
    (if (null? prefix) (lambda (a b) (consume (list a b)))
      (let (group (car prefix)) (lambda (a b) (consume (list group a b))))))
  (for-each (lambda (node) (emit node node)) diagonals)
  (for-each (lambda (a) (for-each (lambda (b) (emit a b) (emit b a)) rights)) lefts))

(def (injection-view prefix diagonals lefts rights count)
  (def (emit consume a b) (consume (append prefix (list a b))))
  (def (visit columns key consume)
    (unless (and (list? columns) (list? key) (= (length columns) (length key))
                 (andmap (lambda (n) (and (exact-integer? n) (>= n 0)
                                          (< n (+ 2 (length prefix))))) columns))
      (error "invalid ASCENT eqrel view key"))
    (if (null? columns)
      ;; Full export retains the direct interleaved writer, without query state.
      (write-injection! prefix diagonals lefts rights consume)
      (let (offset (length prefix))
        (when (andmap (lambda (column value)
                       (or (>= column offset) (equal? (list-ref prefix column) value))) columns key)
          (let ((left-key (compile-coordinate-key offset columns key))
                (right-key (compile-coordinate-key (+ offset 1) columns key)))
            (for-each (lambda (node)
              (when (and (coordinate-accepts? left-key node) (coordinate-accepts? right-key node))
                (emit consume node node))) diagonals)
            (visit-selected-members! left-key right-key lefts rights (cut emit consume <> <>)))))))
  (make-relation-view #f #f 0 'delta count
    (+ (length diagonals) (length lefts) (length rights)) visit
    (lambda (row)
      (let (found? #f)
        (visit (iota (length row)) row (lambda (_) (set! found? #t))) found?)) #f #f))

;;; Preflight counts before changing the owner. Member spines are replaced with
;;; append, not destructively modified, so frontiers and old cuts remain stable.
;; : (forall (a) (-> EqRelState Row Natural (-> Prefix Members Members Members Natural a) a))
;; : (-> EqRelState Row Natural InjectionPublisher Publication)
(def (admit-injection! state row budget finish)
  (let* ((components (eqrel-state-components state)) (width (length row))
         (_ (unless (memq width '(2 3))
              (error "ASCENT eqrel requires two or three columns" row)))
         (group (if (= width 3) (car row) #f))
         (prefix (if (= width 3) (list group) []))
         (pair (if (= width 3) (cdr row) row))
         (left (car pair)) (right (cadr pair)) (same-node? (equal? left right))
         (left-key (member-key width group left))
         (right-key (if same-node? left-key (member-key width group right)))
         (a (hash-get components left-key))
         (b (if same-node? a (hash-get components right-key)))
         (left-size (if a (eqrel-component-size a) 1))
         (right-size (if b (eqrel-component-size b) 1))
         (merge? (not (or same-node? (and a b (eq? a b)))))
         (diagonals (append (if a [] (list left))
                           (if (or b same-node?) [] (list right))))
         (needed (+ (length diagonals) (if merge? (* 2 left-size right-size) 0))))
    (when (> needed budget) (error "ASCENT eqrel output fact budget exceeded"))
    (unless a (set! a (make-eqrel-component (list left) 1)) (hash-put! components left-key a))
    (unless b
      (set! b (if same-node? a (make-eqrel-component (list right) 1)))
      (hash-put! components right-key b))
    (let ((lefts (if merge? (eqrel-component-members a) []))
          (rights (if merge? (eqrel-component-members b) [])))
      (when merge?
        (let* ((large (if (>= left-size right-size) a b))
               (small (if (eq? large a) b a)) (members (eqrel-component-members small)))
          (for-each (lambda (node) (hash-put! components (member-key width group node) large)) members)
          (eqrel-component-members-set! large (append members (eqrel-component-members large)))
          (eqrel-component-size-set! large (+ left-size right-size))))
      (eqrel-state-count-set! state (+ (eqrel-state-count state) needed))
      (finish prefix diagonals lefts rights needed))))

;; Frozen engine frontiers retain member spines; synchronous replay owns its
;; collector instead. Both consumers use exactly the same admission kernel.
;; : (-> EqRelState Row Natural FrozenView)
(def (gerbil-ascent-eqrel-insert! state row budget)
  (admit-injection! state row budget injection-view))

;; gerbil-ascent-eqrel-replay-insert!
;; : (-> EqRelState Row Natural (-> Natural (Maybe RowWriter)) Void)
;; | doc m%
;;     Admit one ordered replay injection, then request its synchronous writer.
;;     The factory observes the complete count before any row is emitted and
;;     may decline old frontiers. No temporary view or exported tuple is retained.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-eqrel-replay-insert! state '(1 2) 4 (lambda (_) displayln))
;;     ;; => fresh diagonals followed by interleaved forward/reverse pairs
;;     ```
;;   %
(def (gerbil-ascent-eqrel-replay-insert! state row budget writer)
  (admit-injection! state row budget
    (lambda (prefix diagonals lefts rights count)
      (let (emit (writer count))
        (when emit (write-injection! prefix diagonals lefts rights emit))))))

;; The public eager extension retains its row protocol for noncanonical indexes
;; and custom Provider compositions. Canonical engine routes consume views.
(def (gerbil-ascent-eqrel-extension state _all _pending row budget)
  (gerbil-ascent-view-rows (gerbil-ascent-eqrel-insert! state row budget)))

(def (capture state indexed?)
  (let ((seen (make-hash-table-eq)) (blocks [])
        (nodes (hash-length (eqrel-state-components state))))
    (hash-for-each (lambda (key component)
      (unless (hash-get seen component)
        (hash-put! seen component #t)
        (let (spine (eqrel-component-members component))
          (set! blocks (cons (make-rectangle (if (= (car key) 3) (list (cadr key)) []) spine spine) blocks)))))
      (eqrel-state-components state))
    (make-eqrel-cut (eqrel-state-count state)
      (gerbil-ascent-rectangle-view blocks (eqrel-state-count state) (* 2 nodes) indexed?))))

(def (gerbil-ascent-eqrel-freeze state (indexed? #t))
  (let (cut (capture state indexed?))
    (eqrel-state-published-set! state cut)
    (eqrel-cut-view cut)))

;;; Collapse the staged union to total-minus-origin. Both lookup carriers are
;;; frozen and linear in active members. Consecutive source appends retain the
;;; earlier delta origin; a fresh derived round uses the previous total cut.
(def (gerbil-ascent-eqrel-publish! state count (indexed? #t))
  (let* ((published (eqrel-state-published state))
         (origin (if (= count (- (eqrel-state-count state) (eqrel-cut-count published)))
                   published (eqrel-state-origin state)))
         (next (capture state indexed?)) (total (eqrel-cut-view next)))
    (unless (= count (- (eqrel-cut-count next) (eqrel-cut-count origin)))
      (error "ASCENT eqrel delta origin mismatch"))
    (let (delta (if (= (eqrel-cut-count origin) 0) total
                   (gerbil-ascent-view-difference total (eqrel-cut-view origin) count)))
      (eqrel-state-origin-set! state origin)
      (eqrel-state-published-set! state next)
      (values total delta))))

;; Observe private active members and concrete cardinality without tuple expansion.
(def (gerbil-ascent-eqrel-observation state)
  (list (hash-length (eqrel-state-components state)) (eqrel-state-count state)))
