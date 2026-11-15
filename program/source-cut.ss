;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Actor Session source transactions. Cuts own row list spines and dense slot
;;; headers. Published cuts are read-only; a failed preparation changes nothing.
(import (only-in "scheme-checked.ss" relational-scalar?))
(export gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows
        gerbil-ascent-source-cut-update gerbil-ascent-source-cut-scalar?
        gerbil-ascent-source-cut-export-mask gerbil-ascent-source-cut-initial-lane
        source-slot-newest-first source-slot-count)
(defstruct source-slot (newest-first rows count scalar?) final: #t)
(defstruct source-change (position rows count) final: #t)
(defstruct source-cut (slots count))

;;; Newest-first is the evaluator's initial lane. Appends allocate one
;;; detached outer pair per admitted occurrence and borrow the old suffix.
;;; Force the chronological view only when the declaration needs it.
;; : (-> OwnedRows Natural Boolean SourceSlot)
(def (published-source-slot newest-first count scalar?)
  (make-source-slot newest-first (delay-atomic (reverse newest-first)) count scalar?))

(def (source-position positions name)
  (let (slot (hash-get positions name))
    (unless slot (error "unknown ASCENT relation" name))
    (- slot 1)))

(def (source-check-rows! arities position name rows)
  (let (width (vector-ref arities position))
    (unless (and (list? rows)
                 (andmap (lambda (row) (and (list? row) (= (length row) width))) rows))
      (error "invalid ASCENT actor Session source rows" name rows))))

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

;; : (-> NamePositions Arities [(Name . Rows)] SourceCut)
(def (gerbil-ascent-make-source-cut positions arities sources)
  (let ((slots (make-vector (vector-length arities))) (count 0))
    (for-each
     (lambda (entry)
       (let ((position (source-position positions (car entry))) (input (cdr entry)))
         (source-check-rows! arities position (car entry) input)
         (let-values (((rows size scalar?) (copy-source-rows input [] #t)))
           (vector-set! slots position (published-source-slot rows size scalar?))
           (set! count (+ count size))))) sources)
    (make-source-cut slots count)))

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
  (let* ((prepared (map (lambda (entry)
                       (let* ((position (source-position positions (car entry)))
                              (rows (cdr entry)))
                         ;; Validate the entire batch before duplicates/budget,
                         ;; but retain no copied row spines on rejected work.
                         (source-check-rows! arities position (car entry) rows)
                         (make-source-change position rows (length rows)))) replacements))
         ;; Empty/single replacements cannot duplicate a position. Do not build
         ;; a transaction membership table for the common single-source update.
         (seen (and (pair? prepared) (pair? (cdr prepared)) (make-hash-table-eq)))
         (old-slots (source-cut-slots cut))
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
             (let-values (((rows added scalar?)
                           (copy-source-rows (source-change-rows entry)
                             (if append? (source-slot-newest-first previous) [])
                             (or (not append?) (source-slot-scalar? previous)))))
               (vector-set! slots position
                 (published-source-slot rows
                   (+ added (if append? (source-slot-count previous) 0)) scalar?)))))) prepared)
      (make-source-cut slots count))))
