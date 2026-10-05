;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Actor Session source transactions. Cuts own row list spines and dense slot
;;; headers. Published cuts are read-only; a failed preparation changes nothing.
(export gerbil-ascent-make-source-cut gerbil-ascent-source-cut-rows
        gerbil-ascent-source-cut-update)
(defstruct source-slot (rows count))
(defstruct source-cut (slots count))

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
         (vector-set! slots position (make-source-slot rows size))
         (set! count (+ count size)))) sources)
    (make-source-cut slots count)))

;; : (-> SourceCut Natural Rows)
(def (gerbil-ascent-source-cut-rows cut position)
  (source-slot-rows (vector-ref (source-cut-slots cut) position)))

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
                         (cons position (make-source-slot rows (length rows))))) replacements))
         ;; Empty/single replacements cannot duplicate a position. Do not build
         ;; a transaction membership table for the common single-source update.
         (seen (and (pair? prepared) (pair? (cdr prepared)) (make-hash-table-eq)))
         (old-slots (source-cut-slots cut))
         (count (source-cut-count cut)))
    (for-each
     (lambda (entry)
       (let* ((position (car entry)) (incoming (cdr entry))
              (previous (vector-ref old-slots position)))
         (when seen
           (when (hash-get seen position)
             (error "duplicate ASCENT actor Session replacement"))
           (hash-put! seen position #t))
         (set! count (+ count (source-slot-count incoming)
                       (if append? 0 (- (source-slot-count previous))))))) prepared)
    (when (> count limit) (error "ASCENT actor Session input fact budget exceeded"))
    ;; Only admitted work allocates detached row spines and append prefixes.
    ;; Preparation leaves old slot headers, rows and counts untouched.
    (let (slots (vector-copy old-slots))
      (for-each
       (lambda (entry)
         (let* ((position (car entry)) (incoming (cdr entry))
                (previous (vector-ref old-slots position))
                (rows (map (lambda (row) (map (lambda (value) value) row))
                           (source-slot-rows incoming))))
           (vector-set! slots position
             (if append?
               (make-source-slot (append (source-slot-rows previous) rows)
                                 (+ (source-slot-count previous) (source-slot-count incoming)))
               (make-source-slot rows (source-slot-count incoming)))))) prepared)
      (make-source-cut slots count))))
