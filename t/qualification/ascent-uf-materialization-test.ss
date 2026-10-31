;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view :gerbil-ascent/program/view-replay
        :gerbil-ascent/table/trrel-uf
        :gerbil-ascent/t/performance/uf-materialization/fixture
        (prefix-in :gerbil-ascent/t/performance/uf-dense/reference-view-replay old-))
(export ascent-uf-materialization-test)
(def (stream view)
  (let (rows [])
    (gerbil-ascent-for-each-row (lambda (row) (set! rows (cons row rows))) view)
    (reverse! rows)))
(def ascent-uf-materialization-test
  (test-suite "UF complete export order and detached row ownership"
    (test-case "full frozen view and replay scenarios match ordered baseline and independent truth"
      (for-each (lambda (scenario)
        (check-equal? (materialized-rows (ui-prepare #f scenario) scenario #f)
                      (materialized-rows (ui-prepare #t scenario) scenario #t))
        (ui-expected (ui-prepare #t scenario) scenario))
        '(dense grouped replay sparse small delta select)))
    (test-case "arbitrary prefixes, empty axes and repeated values preserve descriptor order"
      (for-each (lambda (prefix)
        (for-each (lambda (indexed?)
          (let* ((blocks (list (make-rectangle prefix '(2 1 2) '(4 3))
                              (make-rectangle prefix [] '(8))
                              (make-rectangle prefix '(8) [])
                              (make-rectangle prefix '(9) '(7))))
                 (view (gerbil-ascent-rectangle-view blocks 7 12 indexed?))
                 (expected (map (cut append prefix <>) '((2 4) (2 3) (1 4) (1 3) (2 4) (2 3) (9 7))))
                 (first (gerbil-ascent-view-rows view)) (second (gerbil-ascent-view-rows view)))
            (check-equal? first expected) (check-equal? (stream view) expected)
            (set-car! (car first) 999) (set-cdr! first [])
            (check-equal? second expected) (check-equal? (gerbil-ascent-view-rows view) expected)
            (check-equal? (stream (gerbil-ascent-view-select view (list (length prefix)) '(1)))
                          (map (cut append prefix <>) '((1 4) (1 3)))))) '(#f #t)))
        '(() (0) (#f) (scope label))))
    (test-case "source derived skip and refusal replay preserve complete ordered cuts"
      (let* ((events '((derived (0 2 0)) (source (0 0 1) (0 1 2) (0 0 1))))
             (before '((source (0 0 1) (0 1 2) (0 0 1)))))
        (for-each (lambda (delta?)
          (for-each (lambda (skip)
            (check-equal? (gerbil-ascent-small-journal-export events car cdr 100 skip delta?)
                          (old-gerbil-ascent-small-journal-export events car cdr 100 skip delta?))) '(0 6))) '(#f #t))
        (check-exception (gerbil-ascent-small-journal-export events car cdr 8 0 #f) true)
        (check-equal? (gerbil-ascent-small-journal-export before car cdr 100 6 #t) [])
        (check-equal? (gerbil-ascent-small-journal-export events car cdr 100 0 #f)
                      (old-gerbil-ascent-small-journal-export events car cdr 100 0 #f))))
    (test-case "UF retained exports survive whole SCC retirement and public mutation"
      (let (state (gerbil-ascent-trrel-uf-state))
        (for-each (cut gerbil-ascent-trrel-uf-count-insert! state <> 1000) '((0 1) (1 2) (2 3)))
        (let* ((cut (gerbil-ascent-trrel-uf-freeze state #t))
               (saved (gerbil-ascent-view-rows cut)) (public (gerbil-ascent-view-rows cut)))
          (set-car! (car public) 999)
          (gerbil-ascent-trrel-uf-count-insert! state '(3 0) 1000)
          (check-equal? (gerbil-ascent-view-rows cut) saved)
          (check-equal? (stream cut) saved)
          (check-equal? (length (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-freeze state))) 16))))))
