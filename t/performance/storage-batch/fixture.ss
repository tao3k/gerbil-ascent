;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/objects gerbil-ascent-relation gerbil-ascent-program)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (rename-in (only-in :gerbil-ascent/t/performance/storage-batch/reference-evaluate
                           gerbil-ascent-make-engine)
                   (gerbil-ascent-make-engine old-make-engine)))
(export storage-batch-provider storage-batch-program storage-batch-engine-run storage-batch-rows)
(def (storage-batch-provider expand (observe (lambda (_all _delta) #f)))
  (.o (:: @ gerbil-ascent-set-storage-provider)
      (.extend-rows (lambda (_state all delta row _budget) (observe all delta) (expand row)))))
(def (storage-batch-program width expand (limit 8192) (observe (lambda (_all _delta) #f)))
  (gerbil-ascent-program
   (list (gerbil-ascent-relation 'input width [] gerbil-ascent-hash-index-provider
                                (storage-batch-provider expand observe)))
   [] 16 16 limit))
(def (storage-batch-rows result) ((.ref result 'rows-of) 'input))
(def (storage-batch-engine-run old? program row (appends 1))
  (let* ((engine ((if old? old-make-engine gerbil-ascent-make-engine) program #t))
         (run (.ref engine '.run)))
    (run)
    (for-each (lambda (_) ((.ref engine '.append-source!) 'input row)) (iota appends))
    (run)))
