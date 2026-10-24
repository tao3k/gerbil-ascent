;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Actor Session source transactions. Cuts own row list spines and dense slot
;;; headers. Published cuts are read-only; a failed preparation changes nothing.
(import (only-in "source-log.ss" gerbil-ascent-source-log-rows))
(export gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows
        gerbil-ascent-source-cut-update)
(defstruct source-slot (base additions rows count) final: #t)
(defstruct source-change (position rows count) final: #t)
(defstruct source-cut (slots count))

;;; Published slots own row spines. Delay only header materialization, not
;;; caller admission or copying. Atomic force shares one ordered result among
;;; readers; the thunk captures log roots, never a previous cut or its cache.
;; : (-> OwnedRows ReversedAdditions Natural SourceSlot)
(def (published-source-slot base additions count)
  (make-source-slot base additions
    (if (null? additions) base
      (delay-atomic (gerbil-ascent-source-log-rows base additions))) count))

;;; Detached incoming rows extend only the reversed addition spine. Historical
;;; row headers are shared read-only until the selected cut is observed.
;; : (-> SourceSlot OwnedRows Natural SourceSlot)
(def (append-source-slot previous rows count)
  (if (null? rows) previous
    (published-source-slot (source-slot-base previous)
      (foldl cons (source-slot-additions previous) rows)
      (+ (source-slot-count previous) count))))

(def (source-position positions name)
  (let (slot (hash-get positions name))
    (unless slot (error "unknown ASCENT relation" name))
    (- slot 1)))

(def (source-check-rows! arities position name rows)
  (let (width (vector-ref arities position))
    (unless (and (list? rows)
                 (andmap (lambda (row) (and (list? row) (= (length row) width))) rows))
      (error "invalid ASCENT actor Session source rows" name rows))))

(def (source-copy-rows arities position name rows)
  (source-check-rows! arities position name rows)
  (map (lambda (row) (map (lambda (value) value) row)) rows))

;; : (-> NamePositions Arities [(Name . Rows)] SourceCut)
(def (gerbil-ascent-make-source-cut positions arities sources)
  (let ((slots (make-vector (vector-length arities))) (count 0))
    (for-each
     (lambda (entry)
       (let* ((position (source-position positions (car entry)))
              (rows (source-copy-rows arities position (car entry) (cdr entry)))
              (size (length rows)))
         (vector-set! slots position (published-source-slot rows [] size))
         (set! count (+ count size)))) sources)
    (make-source-cut slots count)))

;; : (-> SourceCut Natural Rows)
(def (gerbil-ascent-source-cut-rows cut position)
  (force (source-slot-rows (vector-ref (source-cut-slots cut) position))))

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
                (previous (vector-ref old-slots position))
                (rows (map (lambda (row) (map (lambda (value) value) row))
                           (source-change-rows entry))))
           (vector-set! slots position
             (if append?
               (append-source-slot previous rows (source-change-count entry))
               (published-source-slot rows [] (source-change-count entry)))))) prepared)
      (make-source-cut slots count))))
