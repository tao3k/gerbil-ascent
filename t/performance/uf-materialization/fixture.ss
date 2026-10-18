;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/relation-view
        :gerbil-ascent/program/view-replay
        :gerbil-ascent/table/storage
        (prefix-in :gerbil-ascent/program/view-state current-)
        (prefix-in :gerbil-ascent/t/performance/uf-materialization/reference-view-state prior-)
        (prefix-in :gerbil-ascent/t/performance/uf-materialization/reference-relation-view old-)
        (prefix-in :gerbil-ascent/t/performance/uf-materialization/reference-view-replay old-))
(export ui-prepare ui-consume ui-expected materialized-rows)
(def (size scenario) (case scenario ((dense grouped) 256) ((replay) 192) ((delta) 128) ((small) 1) (else 64)))
(def (grouped? scenario) (memq scenario '(grouped replay)))
(def (events scenario)
  (let* ((n (size scenario)) (prefix (if (grouped? scenario) '(7) []))
         (edges (map (lambda (i) (append prefix (list i (modulo (+ i 1) n)))) (iota n))))
    (list (cons 'source edges))))
(def (blocks scenario constructor)
  (let* ((n (size scenario)) (members (iota n)) (prefix (if (grouped? scenario) '(7) [])))
    (case scenario
      ((sparse select) (map (lambda (i) (constructor [] (list i) (list i))) members))
      (else (list (constructor prefix members members))))))
(def (delta-cut old?)
  (let* ((n 128) (edges (map (lambda (i) (list i (modulo (+ i 1) n))) (iota n)))
         (state (gerbil-ascent-storage-engine-state gerbil-ascent-trrel-uf-storage-provider))
         (all (vector #f)) (delta (vector #f)) (all-size (vector 0)) (delta-size (vector 0))
         (all-version (vector 0)) (delta-version (vector 0)) (frontier #f))
    (for-each (lambda (row) (set! frontier (gerbil-ascent-storage-view-extension! state row 1000000))) edges)
    ((if old? prior-gerbil-ascent-commit-view! current-gerbil-ascent-commit-view!)
      0 state frontier all delta all-size delta-size all-version delta-version 'reach 0
      (list ((if old? prior-gerbil-ascent-view-journal-event current-gerbil-ascent-view-journal-event) 'source edges)) #f)
    (vector-ref delta 0)))
(def (ui-prepare old? scenario)
  (cond ((eq? scenario 'replay) (events scenario))
        ((eq? scenario 'delta) (delta-cut old?))
        (else ((if old? old-gerbil-ascent-rectangle-view gerbil-ascent-rectangle-view)
      (blocks scenario (if old? old-make-rectangle make-rectangle))
      (if (memq scenario '(sparse select)) (size scenario) (expt (size scenario) 2))
      (+ (size scenario) 1) #t))))
(def (materialized-rows state scenario old?)
  (case scenario
    ((delta) (gerbil-ascent-view-rows state))
    ((replay) ((if old? old-gerbil-ascent-small-journal-export gerbil-ascent-small-journal-export)
                state car cdr 1000000 0 #f))
    ((select) (let (rows [])
                ((if old? old-gerbil-ascent-for-each-row gerbil-ascent-for-each-row)
                  (lambda (row) (set! rows (cons row rows)))
                  ((if old? old-gerbil-ascent-view-select gerbil-ascent-view-select) state '(0) '(32)))
                (reverse! rows)))
    (else ((if old? old-gerbil-ascent-view-rows gerbil-ascent-view-rows) state))))
(def (ui-expected state scenario)
  (let* ((rows (materialized-rows state scenario #t))
         (current (materialized-rows (ui-prepare #f scenario) scenario #f))
         (n (size scenario))
         (wanted (case scenario
                   ((select) '((32 32)))
                   ((delta) (apply append (map (lambda (a) (map (cut list a <>) (iota a))) (iota n))))
                   ((sparse) (map (lambda (i) (list i i)) (iota n)))
                   (else (apply append (map (lambda (a)
                     (map (lambda (b) (if (grouped? scenario) (list 7 a b) (list a b))) (iota n))) (iota n))))))
         (seen (list->hash-table (map (cut cons <> #t) rows))))
    (unless (and (equal? rows current) (= (length rows) (length wanted))
                 (= (hash-length seen) (length wanted)) (andmap (cut hash-get seen <>) wanted))
      (error "UF export independent closure or ordered baseline mismatch" scenario))
    (summary rows)))

;; ASP retains each returned observation. Consume the complete row spine here,
;; then return bounded metadata; the timed call still allocates all public rows.
;; Full ordered correspondence and independent membership are checked above.
(def (summary rows)
  (if (null? rows) '(0 #f #f)
    (list (length rows) (car rows) (last rows))))
(def (ui-consume state scenario old?)
  (summary (materialized-rows state scenario old?)))
