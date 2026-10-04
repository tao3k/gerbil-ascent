;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One engine's physical indexes over live all/delta vectors. Metadata plans
;;; stay immutable; source admission and row/version publication stay in evaluate.
(import (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-index-key
                 gerbil-ascent-index-key/terms gerbil-ascent-index-value)
        (only-in :gerbil-ascent/table/access gerbil-ascent-physical-index-build
                 gerbil-ascent-physical-index-extend! gerbil-ascent-physical-index-rows
                 gerbil-ascent-physical-index-single-rows)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider))
(export gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance!)

(defstruct row-indexes (rows advance!))

;; gerbil-ascent-make-row-indexes
;;   : (-> Rows Rows Sizes Sizes Versions Versions Providers RowIndexes)
;;   | doc m%
;;       Own all/delta physical caches for one engine. The engine updates the
;;       supplied row, size and version vectors; indexes extend only admitted rows.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version providers)
;;       ;; => engine-local lookup and incremental extension procedures
;;       ```
;;     %
(def (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version index-providers)
  (let ((all-indexes (make-vector (vector-length all) #f))
        (delta-indexes (make-vector (vector-length delta) #f)))
      (def (indexed-rows atom environment use-delta? slot-terms)
        (let* ((index (vector-ref atom 0))
               (columns (vector-ref atom 2))
               (rows (vector-ref (if use-delta? delta all) index)))
          (if (or (null? columns)
                  (< (vector-ref (if use-delta? delta-size all-size)
                                 index)
                     32))
            rows
            (let* ((caches (if use-delta? delta-indexes all-indexes))
                   (cache
                    (or (vector-ref caches index)
                        (let (fresh (make-hash-table))
                          (vector-set! caches index fresh)
                          fresh)))
                   (version (vector-ref
                             (if use-delta? delta-version all-version)
                             index))
                   (entry (hash-get cache columns))
                   (lookup
                    (if (and entry (= (car entry) version))
                      (cdr entry)
                      (let (built (gerbil-ascent-physical-index-build
                                   (vector-ref index-providers index) rows columns))
                        (hash-put! cache columns (cons version built))
                        built)))
                   (provider (vector-ref index-providers index)))
              ;; Only this trusted representation consumes a scalar. Custom
              ;; receivers retain list keys, callbacks and their lookup order.
              (if (and (eq? provider gerbil-ascent-hash-index-provider)
                       (null? (cdr columns)))
                (gerbil-ascent-physical-index-single-rows
                 lookup (gerbil-ascent-index-value
                         (car (vector-ref atom 4)) environment
                         (and slot-terms (car slot-terms))))
                (let (key (if slot-terms
                            (gerbil-ascent-index-key
                             (vector-ref atom 1) columns environment slot-terms)
                            (gerbil-ascent-index-key/terms
                             (vector-ref atom 4) environment)))
                  (gerbil-ascent-physical-index-rows provider lookup key)))))))
      (def (advance-all-indexes! index new-rows (reverse-order? #f))
        (let (cache (vector-ref all-indexes index))
          (when (and cache (pair? new-rows))
            (let ((rows (if reverse-order? (reverse new-rows) new-rows))
                  (version (vector-ref all-version index))
                  (provider (vector-ref index-providers index)))
              (hash-for-each
               (lambda (columns entry)
                 (when (= (car entry) version)
                   (hash-put! cache columns
                     (cons (+ version 1)
                           (gerbil-ascent-physical-index-extend!
                            provider (cdr entry) rows columns)))))
               cache)))))
    (make-row-indexes indexed-rows advance-all-indexes!)))
