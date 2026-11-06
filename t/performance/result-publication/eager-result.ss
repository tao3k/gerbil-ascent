;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Publish persistent ordered rows. A retained engine owns the optional cache;
;;; every publication owns its vector, while unchanged row spines may be shared.
(export gerbil-ascent-publication-cache gerbil-ascent-publish-rows)

;; gerbil-ascent-publication-cache
;;   : (-> Nat PublicationCache)
;;   | doc m%
;;       Allocate two private cursor vectors for one retained engine. The cache
;;       is never attached to a public result or shared across engines.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-publication-cache 2)
;;       ;; => private roots and ordered rows for two relations
;;       ```
;;     %
(def (gerbil-ascent-publication-cache count)
  (cons (make-vector count #f) (make-vector count #f)))

;; gerbil-ascent-publish-rows
;;   : (-> RowsVector PublicationCache RowsVector)
;;   | doc m%
;;       Publish a fresh result vector and reuse ordered row spines only when
;;       the engine's persistent row root is unchanged. Engine-owned append
;;       prefixes and lattice replacement always change that root.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-publish-rows (vector '((2) (1)))
;;                                  (gerbil-ascent-publication-cache 1))
;;       ;; => a fresh vector containing '((1) (2))
;;       ```
;;     %
(def (gerbil-ascent-publish-rows all cache)
  (let (snapshots (make-vector (vector-length all) []))
    (publish-index! all (car cache) (cdr cache) snapshots 0)
    snapshots))

;; : (-> RowsVector RowsVector RowsVector RowsVector Nat Void)
(def (publish-index! all roots ordered snapshots index)
  (when (< index (vector-length all))
    (let (rows (vector-ref all index))
      (unless (eq? rows (vector-ref roots index))
        (vector-set! ordered index (reverse rows))
        (vector-set! roots index rows))
      (vector-set! snapshots index (vector-ref ordered index)))
    (publish-index! all roots ordered snapshots (+ index 1))))
