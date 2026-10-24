;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Persistent admitted source rows: forward base plus newest-first additions.
;;; Callers own snapshot headers and keep all admitted row/list spines read-only.
(export gerbil-ascent-source-log-rows gerbil-ascent-source-log-equal?)
;; gerbil-ascent-source-log-rows
;; : (forall (a) (-> [a] [a] [a]))
;;   : (-> SourceBase ReversedAdditions OrderedSourceRows)
;;   | doc m%
;;       Reuse the immutable base when no additions exist. Otherwise build new
;;       list headers in original source order, preserving each row's identity.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-source-log-rows '((1)) '((3) (2)))
;;       ;; => '((1) (2) (3))
;;       ```
;;     %
(def (gerbil-ascent-source-log-rows base additions)
  (if (null? additions) base (append base (reverse additions))))

;; gerbil-ascent-source-log-equal?
;; : (forall (a) (-> [a] [a] [a] Boolean))
;;   : (-> SourceBase ReversedAdditions OrderedSourceRows Boolean)
;;   | doc m%
;;       Compare ordered source values without copying base headers. Preserve
;;       duplicate multiplicity and compare additions only after the base matches.
;;       All source lists belong to admitted persistent snapshots.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-source-log-equal? '((1)) '((3) (2)) '((1) (2) (3)))
;;       ;; => #t
;;       ```
;;     %
(def (gerbil-ascent-source-log-equal? base additions rows)
  (if (null? additions) (equal? base rows)
    ;; foldl carries only a candidate suffix or #f. A rejected prefix keeps
    ;; skipping equality checks; no base headers or tuple states are allocated.
    (let (tail (foldl (lambda (row remaining)
                       (and (pair? remaining) (equal? row (car remaining))
                            (cdr remaining))) rows base))
      (and tail (equal? (reverse additions) tail)))))
