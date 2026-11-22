;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Actor Session source transactions. Cuts own row list spines and dense slot
;;; headers. Published cuts are read-only; a failed preparation changes nothing.
(import (only-in :std/iter for/fold in-list)
        (only-in :std/struct/rbtree RBTree rbtree-get rbtree-put rbtree-remove
                 rbtree-empty? rbtree-for-each)
        (only-in :gerbil-ascent/core/relation-view make-relation-view)
        (only-in :gerbil-ascent/core/view-value
                 make-ordered-binary-visitors make-packed-binary-visitors
                 gerbil-ascent-binary-destination-end
                 gerbil-ascent-visit-admitted-view-parts!)
        (only-in "scheme-checked.ss" relational-scalar?))
(export gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows
        gerbil-ascent-source-cut-update gerbil-ascent-source-cut-scalar?
        gerbil-ascent-source-cut-export-mask gerbil-ascent-source-cut-initial-lane
        gerbil-ascent-source-cut-terminal-slot gerbil-ascent-source-cut-edit-edge
        source-slot-newest-first source-slot-count source-slot-view source-slot-rows
        source-slot-binary-visitor source-slot-validated-binary-view source-slot-packed-extra)
(defstruct source-slot (lane rows count scalar? view cells journal) final: #t)
(defstruct edge-journal (base hidden offsets appended next) final: #t)
(defstruct source-change (position rows count affine) final: #t)
(defstruct affine-source (count left right left-stride right-stride) final: #t)
(defstruct source-cut (slots count packed-source recursive-source? alternate))

;;; Newest-first is the evaluator's initial lane. Appends allocate one
;;; detached outer pair per admitted occurrence and borrow the old suffix.
;;; Force the chronological view only when the declaration needs it.
;; : (-> OwnedRows Natural Boolean SourceSlot)
(def (published-source-slot newest-first count scalar?)
  (make-source-slot newest-first (delay-atomic (reverse newest-first)) count scalar? #f #f #f))

(def (source-slot-newest-first (slot :- source-slot))
  (let (lane slot.lane) (if (promise? lane) (force lane) lane)))

(def (packed-source-lane cells)
  (let (end (s64vector-length cells))
    (let collect ((i 0) (rows []))
      (if (fx= i end) rows
        (collect (fx+ i 2)
          (cons (list (##s64vector-ref cells i) (##s64vector-ref cells (fx+ i 1))) rows))))))

;; Both representations keep their numeric load inlined at scan and lookup
;; sites. Ordinals address rows; only the vector adapter scales by width.
(defrule (binary-source-view count ascending? indexed? read-left read-right copy-cells)
  (let ()
    (def (column-index columns key)
      (let search ((columns columns) (key key))
        (cond ((null? columns) #f)
              ((= (car columns) 0) (car key))
              (else (search (cdr columns) (cdr key))))))
    (def (lookup origin)
      (let search ((lo 0) (hi count))
        (and (fx< lo hi)
             (let* ((mid (fx+ lo (fxquotient (fx- hi lo) 2)))
                    (key (read-left mid)))
               (cond ((fx= key origin) mid)
                     ((if ascending? (fx< key origin) (fx< origin key)) (search (fx+ mid 1) hi))
                     (else (search lo mid)))))))
    (def (matches? left right columns key)
      (or (null? columns)
          (and (equal? (if (= (car columns) 0) left right) (car key))
               (matches? left right (cdr columns) (cdr key)))))
    (defrule (visit-fields columns key consume)
      (let ()
        (def (visit! index)
          (let ((left (read-left index)) (right (read-right index)))
            (when (matches? left right columns key) (consume left right))))
        (if (null? columns)
          ;; The invocation owns its cursor and needs no query predicate.
          (let loop ((i 0))
            (unless (fx= i count)
              (consume (read-left i)
                       (read-right i))
              (loop (fx+ i 1))))
          (let (origin (and indexed? (column-index columns key)))
            (if (fixnum? origin)
              (let (index (lookup origin)) (when index (visit! index)))
              (let loop ((i 0))
                (unless (fx= i count) (visit! i) (loop (fx+ i 1)))))))))
    (def (visit columns key consume)
      (visit-fields columns key (lambda (left right) (consume (list left right)))))
    (def (parts columns key consume)
      (visit-fields columns key (lambda (left right) (consume [] left right))))
    (def (contains? row)
      (and (pair? row) (pair? (cdr row)) (null? (cddr row)) (fixnum? (car row))
           (if indexed?
             (let (index (lookup (car row)))
               (and index (equal? (cadr row) (read-right index))))
             (let scan ((i 0))
               (and (fx< i count)
                    (or (and (equal? (car row) (read-left i))
                             (equal? (cadr row) (read-right i)))
                        (scan (fx+ i 1))))))))
    (def (export)
      (let collect ((i (fx- count 1)) (rows []))
        (if (fx< i 0) rows
          (collect (fx- i 1)
            (cons (list (read-left i) (read-right i)) rows)))))
    (make-relation-view #f #f 0 'total count count visit contains? export
      (let (copy copy-cells)
        (if copy
          (make-packed-binary-visitors parts parts export copy)
          (make-ordered-binary-visitors parts parts export))))))

(def (packed-source-view cells count ascending? (indexed? #t))
  (binary-source-view count ascending? indexed?
    (lambda (i) (##s64vector-ref cells (fx* i 2)))
    (lambda (i) (##s64vector-ref cells (fx+ (fx* i 2) 1)))
    (lambda (destination start) (s64vector-copy! destination start cells))))

(def (make-affine-source-slot count left right left-stride right-stride)
  (defrule (left-at i) (fx+ left (fx* i left-stride)))
  (defrule (right-at i) (fx+ right (fx* i right-stride)))
  (def (copy! destination start)
    (let (end (gerbil-ascent-binary-destination-end destination start count))
      (let write-fields ((offset start) (x left) (y right))
        (unless (fx= offset end)
          (##s64vector-set! destination offset x)
          (##s64vector-set! destination (fx+ offset 1) y)
          ;; The admitted interval bounds both fields. The final unused
          ;; successor can wrap without being read or written.
          (write-fields (fx+ offset 2) (fxwrap+ x left-stride) (fxwrap+ y right-stride))))))
  (let (lane
        (delay-atomic
          (let collect ((i 0) (rows []))
            (if (fx= i count) rows
              (collect (fx+ i 1) (cons (list (left-at i) (right-at i)) rows))))))
    (make-source-slot lane (delay-atomic (reverse (force lane))) count #t
      (binary-source-view count (fx> left-stride 0) #t
        (lambda (i) (left-at i)) (lambda (i) (right-at i)) copy!)
      #f #f)))

(def (fixnum-binary-row? row)
  (and (pair? row) (pair? (cdr row)) (null? (cddr row))
       (fixnum? (car row)) (fixnum? (cadr row))))

;; Bound the ordinal by both the product and the resulting field.
;; Generic arithmetic here allows an intermediate difference to be a bignum.
(def (affine-last-ordinal first stride cap)
  (cond
   ((fx> stride 0)
    (let (hi (##greatest-fixnum))
      (min cap (quotient hi stride) (quotient (- hi first) stride))))
   ((fx< stride 0)
    (let ((lo (##least-fixnum)) (magnitude (- stride)))
      (min cap (quotient (- lo) magnitude) (quotient (- first lo) magnitude))))
   (else cap)))

;; Prove the numeric representation and canonical row shape in one scan.
;; A failed proof returns to ordinary validation.
(def (try-affine-source rows)
  (and (pair? rows) (pair? (cdr rows))
       (let ((first (car rows)) (second (cadr rows)))
         (and (fixnum-binary-row? first) (fixnum-binary-row? second)
              (let* ((left (car first)) (right (cadr first))
                     (second-x (car second)) (second-y (cadr second))
                     (dx (- second-x left)) (dy (- second-y right)))
                (and (fixnum? dx) (not (fx= dx 0)) (fixnum? dy)
                     (let* ((cap #x3ffffffe)
                            (x-limit (affine-last-ordinal left dx cap))
                            (limit (affine-last-ordinal right dy x-limit)))
                       (let scan ((rest (cddr rows)) (n 2)
                                  (x (fxwrap+ second-x dx)) (y (fxwrap+ second-y dy)))
                         (cond
                          ((null? rest)
                           (and (fx>= n 32) (make-affine-source n left right dx dy)))
                          ((and (fx<= n limit) (pair? rest))
                           (let (row (car rest))
                             (and (pair? row) (eq? x (car row))
                                  (let (tail (cdr row))
                                    (and (pair? tail) (eq? y (car tail)) (null? (cdr tail))
                                         (scan (cdr rest) (fx+ n 1)
                                           (fxwrap+ x dx) (fxwrap+ y dy)))))))
                          (else #f))))))))))

(def (affine-source-slot (source :- affine-source))
  (make-affine-source-slot source.count source.left source.right
    source.left-stride source.right-stride))

;; Copy the admitted occurrence stream into private cells. A mismatch takes
;; the ordinary capture route before the new slot can be installed.
(def (make-packed-source-slot cells count ascending? (ordered? #t))
  (let (lane (delay-atomic (packed-source-lane cells)))
    (make-source-slot lane (delay-atomic (reverse (force lane))) count #t
      (and ordered? (packed-source-view cells count ascending?)) cells #f)))

;; Only the terminal worker calls this after validating distinct source rows.
(def (source-slot-validated-binary-view (slot :- source-slot))
  (let (cells slot.cells)
    (and cells (packed-source-view cells slot.count #f #f))))

;; Internal reader for the recursive index builder. Unordered cells never
;; establish membership or publish a unique source relation on their own.
(def (source-slot-binary-visitor (slot :- source-slot))
  (let ((cells slot.cells) (view slot.view))
    (cond
     (cells
      (lambda (consume)
        (let (end (s64vector-length cells))
          (let visit ((i 0))
            (unless (fx= i end)
              (consume (##s64vector-ref cells i) (##s64vector-ref cells (fx+ i 1)))
              (visit (fx+ i 2)))))))
     (view
      (lambda (consume)
        (gerbil-ascent-visit-admitted-view-parts! view [] []
          (lambda (_ left right) (consume left right)))))
     (else #f))))

;; These maps use the persistent STD operations, including for a nested
;; origin's targets. No published tree or base buffer is ever changed.
(def (edge-number-order a b) (cond ((< a b) -1) ((> a b) 1) (else 0)))
(def (edge-map-get tree left right)
  (alet (targets (rbtree-get tree left)) (rbtree-get targets right)))

(def (edge-map-set tree left right value)
  (let (targets (or (rbtree-get tree left) (RBTree edge-number-order)))
    (let (next (if value (rbtree-put targets right value) (rbtree-remove targets right)))
      (if (rbtree-empty? next) (rbtree-remove tree left) (rbtree-put tree left next)))))

(def (edit-source-slot (slot :- source-slot) insert? left right count)
  (using (journal (or slot.journal
                     (let (empty (RBTree edge-number-order))
                       (make-edge-journal slot empty empty empty 0)))
                  :- edge-journal)
    (let* ((base journal.base)
           (hidden journal.hidden)
           (offsets journal.offsets)
           (appended journal.appended)
           (next journal.next)
           (at (and (not insert?) (edge-map-get offsets left right))))
      (cond (insert?
             (set! offsets (edge-map-set offsets left right next))
             (set! appended (rbtree-put appended next (cons left right)))
             (set! next (+ next 1)))
            (at
             (set! offsets (edge-map-set offsets left right #f))
             (set! appended (rbtree-remove appended at)))
            (else (set! hidden (edge-map-set hidden left right #t))))
      (let (visit-base (or (source-slot-binary-visitor base)
                          (lambda (consume)
                            (for-each (lambda (row) (consume (car row) (cadr row)))
                                      (force (source-slot-rows base))))))
        (def (visit consume)
          (if (rbtree-empty? hidden)
            (visit-base consume)
            (visit-base (lambda (a b) (unless (edge-map-get hidden a b) (consume a b)))))
          (rbtree-for-each (lambda (_ row) (consume (car row) (cdr row))) appended))
        (def (parts columns key consume)
          (def (matches? columns key a b)
            (or (null? columns)
                (and (equal? (if (= (car columns) 0) a b) (car key))
                     (matches? (cdr columns) (cdr key) a b))))
          (visit (lambda (a b) (when (matches? columns key a b) (consume [] a b)))))
        (def (materialize-lane)
          (let (rows [])
            (visit (lambda (a b) (set! rows (cons (list a b) rows))))
            rows))
        (def (export) (reverse! (materialize-lane)))
        (def (copy-fields! destination start)
          (unless (and (fixnum? start) (<= 0 start)
                       (<= (+ start (* 2 count)) (s64vector-length destination)))
            (error "ASCENT source edit buffer span is out of range" start count))
          (let (i start)
            (visit (lambda (a b)
                     (s64vector-set! destination i a)
                     (s64vector-set! destination (+ i 1) b)
                     (set! i (+ i 2))))))
        (def (contains? row)
          (and (pair? row) (pair? (cdr row)) (null? (cddr row))
               (let/cc found
                 (visit (lambda (a b)
                          (when (and (equal? (car row) a) (equal? (cadr row) b)) (found #t))))
                 #f)))
        (let* ((lane (delay-atomic (materialize-lane)))
               (view (make-relation-view #f #f 0 'total count count
                       (lambda (columns key consume)
                         (parts columns key (lambda (_ a b) (consume (list a b)))))
                       contains? export (make-packed-binary-visitors parts parts export copy-fields!))))
          (make-source-slot lane (delay-atomic (reverse (force lane))) count #t view #f
            (make-edge-journal base hidden offsets appended next)))))))

;; Only the Actor owner prepares this cut, against the source identity
;; certified by the worker's retained graph. Presence is checked there
;; before the candidate can be published.
(def (gerbil-ascent-source-cut-edit-edge (cut :- source-cut) position insert? left right limit)
  (let* ((slots (vector-copy cut.slots))
         (slot (vector-ref slots position))
         (delta (if insert? 1 -1))
         (count (+ cut.count delta)))
    (when (> count limit) (error "ASCENT actor Session input fact budget exceeded"))
    (when (and (not insert?) (zero? (source-slot-count slot)))
      (error "ASCENT actor Session cannot delete a missing edge"))
    (vector-set! slots position (edit-source-slot slot insert? left right (+ (source-slot-count slot) delta)))
    (make-source-cut slots count cut.packed-source cut.recursive-source? #f)))

;; The two slots already own their captured fields. Accept exactly one
;; ordered splice and verify the full suffix before returning the edit.
(def (source-slot-packed-extra (long :- source-slot) (short :- source-slot) checkpoint!
                              (locate-successor? #f))
  (let ((more long.cells) (less short.cells))
    (and more less
         (let (end (s64vector-length less))
           (def (same-row? i j)
             (and (fx= (##s64vector-ref more i) (##s64vector-ref less j))
                  (fx= (##s64vector-ref more (fx+ i 1)) (##s64vector-ref less (fx+ j 1)))))
           (def (extra i successor)
             (list (##s64vector-ref more i) (##s64vector-ref more (fx+ i 1)) successor))
           (and (fx= (s64vector-length more) (fx+ end 2))
                (let prefix ((i 0))
                  (checkpoint!)
                  (cond
                   ((fx= i end) (extra i #f))
                   ((same-row? i i) (prefix (fx+ i 2)))
                   (else
                    (let (origin (##s64vector-ref more i))
                      (let suffix ((j i) (successor #f))
                        (checkpoint!)
                        (if (fx= j end) (extra i successor)
                          (and (same-row? (fx+ j 2) j)
                               (suffix (fx+ j 2)
                                 (or successor
                                     (and locate-successor? (fx= origin (##s64vector-ref less j))
                                          (##s64vector-ref less (fx+ j 1)))))))))))))))))

(def (same-packed-source? rows cells size)
  (and cells (fx= size (s64vector-length cells))
       (let same ((remaining rows) (i 0))
         (if (fx= i size) (null? remaining)
           (and (pair? remaining)
                (let (row (car remaining))
                  (and (pair? row) (pair? (cdr row)) (null? (cddr row))
                       (let ((left (car row)) (right (cadr row)))
                         (and (fixnum? left) (fixnum? right)
                              (fx= left (##s64vector-ref cells i))
                              (fx= right (##s64vector-ref cells (fx+ i 1)))
                              (same (cdr remaining) (fx+ i 2)))))))))))

(def (capture-packed-source-slot rows size count recursive-source?)
  (let (cells (make-s64vector size))
    (let capture ((rest rows) (i 0) (last #f) (direction 0))
      (if (fx= i size)
        (and (null? rest)
             (make-packed-source-slot cells count
               (eqv? direction 1) (not (eq? direction 'unordered))))
        (and (pair? rest)
             (let (row (car rest))
               (and (pair? row) (pair? (cdr row)) (null? (cddr row))
                    (let ((left (car row)) (right (cadr row)))
                      (and (fixnum? left) (fixnum? right)
                           (let (direction
                                 (cond ((eq? direction 'unordered) direction)
                                       ((not last) 0)
                                       ((eq? direction 1)
                                        (if (fx< last left) 1 (and recursive-source? 'unordered)))
                                       ((eq? direction -1)
                                        (if (fx< left last) -1 (and recursive-source? 'unordered)))
                                       ((fx< last left) 1)
                                       ((fx< left last) -1)
                                       (else (and recursive-source? 'unordered))))
                             (and direction
                                  (begin
                                    (##s64vector-set! cells i left)
                                    (##s64vector-set! cells (fx+ i 1) right)
                                    (capture (cdr rest) (fx+ i 2) left direction)))))))))))))

(def (try-packed-source-slot rows count (current #f) (alternate #f) (recursive-source? #f))
  (and (fixnum? count) (<= 32 count #x3fffffff) (fixnum? (* count 2))
       (let* ((size (fx* count 2))
              (reused (cond ((same-packed-source? rows current size) current)
                            ((same-packed-source? rows alternate size) alternate)
                            (else #f))))
         (if reused
           (make-packed-source-slot reused count
             (fx< (##s64vector-ref reused 0) (##s64vector-ref reused 2)))
           (capture-packed-source-slot rows size count recursive-source?)))))

(def (source-position positions name)
  (let (slot (hash-get positions name))
    (unless slot (error "unknown ASCENT relation" name))
    (- slot 1)))

;; A declared width bounds tuple validation even for an improper or cyclic
;; row. Count the already validated occurrences before budget preflight.
(def (source-row-count! arities position name rows)
  (def (invalid) (error "invalid ASCENT actor Session source rows" name rows))
  (def (tuple? row remaining)
    (if (zero? remaining)
      (null? row)
      (and (pair? row) (tuple? (cdr row) (- remaining 1)))))
  (let (width (vector-ref arities position))
    (unless (list? rows) (invalid))
    (for/fold (total 0) (row (in-list rows))
      (unless (tuple? row width) (invalid))
      (+ total 1))))

;; Classify the owned copy without changing which host values are admitted.
;; The classification describes the same atoms just copied, never the caller.
(def (copy-source-rows rows tail scalar?)
  (let (count 0)
    (let (reversed
          (foldl
           (lambda (row prior)
             (set! count (+ count 1))
             (cons (map (lambda (value)
                          (when (and scalar? (not (relational-scalar? value)))
                            (set! scalar? #f))
                          value) row) prior))
           tail rows))
      (values reversed count scalar?))))

;; : (-> NamePositions Arities [(Name . Rows)] (Maybe Natural) SourceCut)
(def (gerbil-ascent-make-source-cut positions arities sources
                                    (packed-source #f) (recursive-source? #f))
  (let ((slots (make-vector (vector-length arities))) (count 0))
    (for-each
     (lambda (entry)
       (let* ((position (source-position positions (car entry)))
              (input (cdr entry))
              (affine (and (eqv? packed-source position) (try-affine-source input)))
              (packed (if affine (affine-source-slot affine)
                        (let (size (source-row-count! arities position (car entry) input))
                          (and (eqv? packed-source position)
                               (try-packed-source-slot input size #f #f recursive-source?)))))
              (slot (or packed
                         (let-values (((rows captured scalar?) (copy-source-rows input [] #t)))
                           (published-source-slot rows captured scalar?)))))
         (vector-set! slots position slot)
         (set! count (+ count (source-slot-count slot))))) sources)
    (make-source-cut slots count packed-source recursive-source? #f)))

;; Any target seed keeps the normal evaluator. The exact cut was already
;; validated and charged for source admission before the worker reads it.
(def (gerbil-ascent-source-cut-terminal-slot (cut :- source-cut) source target input-limit output-limit)
  (and (zero? (source-slot-count (vector-ref cut.slots target)))
       (<= cut.count input-limit)
       (<= cut.count output-limit)
       (vector-ref cut.slots source)))

;; : (-> SourceCut Natural Rows)
(def (gerbil-ascent-source-cut-rows cut position)
  (force (source-slot-rows (vector-ref (source-cut-slots cut) position))))

;; : (-> SourceCut Boolean)
(def (gerbil-ascent-source-cut-scalar? (cut :- source-cut))
  (let (slots cut.slots)
    (let check ((index 0))
      (or (= index (vector-length slots))
          (and (source-slot-scalar? (vector-ref slots index)) (check (+ index 1)))))))

;;; Borrow the owner lane through the exact admitted Actor input cut.
;;; Mutable atom keys remain on the ordinary admission path.
;; : (-> SourceCut Natural (Maybe SourceSlot))
(def (gerbil-ascent-source-cut-initial-lane (cut :- source-cut) position)
  (using (slot (vector-ref cut.slots position) :- source-slot)
    (and slot.scalar? slot)))

;;; Only slots containing input rows can expose source-cut row pairs.
;; : (-> SourceCut (Vector Boolean))
(def (gerbil-ascent-source-cut-export-mask (cut :- source-cut))
  (vector-map (lambda (slot) (> (source-slot-count slot) 0)) cut.slots))

;; gerbil-ascent-source-cut-update
;; : (-> SourceCut NamePositions Arities [(Name . Rows)] Boolean Natural SourceCut)
;; | doc m%
;;     Prepare a detached source transaction by dense relation position. Retain
;;     input multiplicity in the budget, validate all rows before duplicates,
;;     and publish no headers until the entire batch fits. Untouched slots are
;;     shared read-only; count deltas never traverse their source rows.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-source-cut-update cut positions arities '((edge (1 2))) #f 100)
;;     ;; => a new cut; cut still owns its previous rows
;;     ```
;;   %
(def (gerbil-ascent-source-cut-update cut positions arities replacements append? limit)
  (let* ((packed-source (source-cut-packed-source cut))
         (prepared (map (lambda (entry)
                       (let* ((position (source-position positions (car entry)))
                              (rows (cdr entry))
                              (affine (and (not append?) (eqv? packed-source position)
                                           (try-affine-source rows))))
                         ;; Validate the entire batch before duplicates/budget.
                         ;; An affine certificate owns numbers, never row spines.
                         (make-source-change position rows
                           (if affine (affine-source-count affine)
                             (source-row-count! arities position (car entry) rows))
                           affine))) replacements))
         ;; Empty/single replacements cannot duplicate a position. Do not build
         ;; a transaction membership table for the common single-source update.
         (seen (and (pair? prepared) (pair? (cdr prepared)) (make-hash-table-eq)))
         (old-slots (source-cut-slots cut))
         (alternate (source-cut-alternate cut))
         (recursive-source? (source-cut-recursive-source? cut))
         (count (source-cut-count cut)))
    (for-each
     (lambda (entry)
       (let* ((position (source-change-position entry))
              (previous (vector-ref old-slots position)))
         (when seen
           (when (hash-get seen position)
             (error "duplicate ASCENT actor Session replacement"))
           (hash-put! seen position #t))
         (set! count (+ count (source-change-count entry)
                       (if append? 0 (- (source-slot-count previous))))))) prepared)
    (when (> count limit) (error "ASCENT actor Session input fact budget exceeded"))
    ;; Only admitted work allocates detached row spines and persistent logs.
    ;; Preparation leaves old slot headers, rows and counts untouched.
    (let (slots (vector-copy old-slots))
      (for-each
       (lambda (entry)
         (let* ((position (source-change-position entry))
                (previous (vector-ref old-slots position)))
           (unless (and append? (zero? (source-change-count entry)))
             (let* ((input (source-change-rows entry))
                    (packed
                     (and (eqv? packed-source position)
                          (let* ((current (and (source-slot-view previous) (source-slot-cells previous)))
                                 (new (cond
                                       ((source-change-affine entry) => affine-source-slot)
                                       ((not append?)
                                        (try-packed-source-slot input (source-change-count entry)
                                          current alternate recursive-source?))
                                       (else #f)))
                                 (next-cells (and new (source-slot-cells new))))
                            ;; Affine slots own only their numeric descriptor.
                            ;; An older packed backing remains owned by any held cut.
                            (set! alternate
                              (cond ((not next-cells) #f)
                                    ((eq? current next-cells) alternate)
                                    ((and current (<= (s64vector-length current) (* 2 1024 1024)))
                                     current)
                                    (else #f)))
                            new))))
               (vector-set! slots position
                 (or packed
                     (let-values (((rows added scalar?)
                                   (copy-source-rows input
                                     (if append? (source-slot-newest-first previous) [])
                                     (or (not append?) (source-slot-scalar? previous)))))
                       (published-source-slot rows
                         (+ added (if append? (source-slot-count previous) 0)) scalar?)))))))) prepared)
      (make-source-cut slots count packed-source recursive-source? alternate))))
