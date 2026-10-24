;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Publish persistent ordered rows. A retained engine owns the optional cache;
;;; every publication owns its vector, while unchanged row spines may be shared.
(export gerbil-ascent-publication-cache gerbil-ascent-publish-rows)

;; : (-> Nat PublicationCache)
(def (gerbil-ascent-publication-cache count)
  (cons (make-vector count #f) (make-vector count #f)))

;; : (-> RowsVector (Maybe PublicationCache) RowsVector)
(def (gerbil-ascent-publish-rows all cache)
  (if (not cache)
    (vector-map reverse all)
    (let* ((count (vector-length all)) (snapshots (make-vector count []))
           (roots (car cache)) (ordered (cdr cache)))
      (let loop ((index 0))
        (when (< index count)
          (let (rows (vector-ref all index))
            (unless (eq? rows (vector-ref roots index))
              (vector-set! ordered index (reverse rows))
              (vector-set! roots index rows))
            (vector-set! snapshots index (vector-ref ordered index)))
          (loop (+ index 1))))
      snapshots)))
