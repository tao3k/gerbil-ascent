;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Preflight slice from program/evaluate.ss at fcb9ed1117cf597b7acdcc2c9b5895cd1bffb1c3.
;;; Only engine vector reads/counts are explicit arguments; publication excluded.
(export old-prepare-storage-batch)
(def (old-prepare-storage-batch expanded width check present count output-limit)
  (let ((batch-seen (and (pair? expanded) (pair? (cdr expanded)) (make-hash-table)))
        (new-rows []))
    (unless (list? expanded)
      (error "ASCENT storage provider returned non-list rows"))
    (for-each
     (lambda (stored)
       (unless (and (list? stored) (= (length stored) width))
         (error "invalid ASCENT storage provider row" stored))
       (when check (check stored))
       (unless (or (hash-get present stored)
                   (and batch-seen (hash-get batch-seen stored)))
         (when batch-seen (hash-put! batch-seen stored #t))
         (set! new-rows (cons stored new-rows))))
     expanded)
    (set! new-rows (reverse new-rows))
    (let (added-count (length new-rows))
      (when (> (+ count added-count) output-limit)
        (error "ASCENT session output fact budget exceeded"))
      (values new-rows added-count))))
