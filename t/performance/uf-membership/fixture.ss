;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/core/relation-view
        (prefix-in "reference-relation-view.ss" old-))
(export ui-prepare ui-consume ui-expected)
(def (rectangle-cut old? size grouped? indexed?)
  (let* ((axis (iota size))
         (prefixes (if grouped? '((0) (7)) '(()))))
    ;; Bind each carrier constructor as syntax. Dynamic optional-argument
    ;; aliases can be lowered to the wrong private entry by native compilation.
    (defrule (build rectangle view)
      (view (map (lambda (prefix) (rectangle prefix axis axis)) prefixes)
        (* (length prefixes) size size) (* size 2) indexed?))
    (if old? (build old-make-rectangle old-gerbil-ascent-rectangle-view)
      (build make-rectangle gerbil-ascent-rectangle-view))))
(def (ui-prepare old? scenario)
  (case scenario
    ((export) (list (rectangle-cut old? 128 #f #t) 16384))
    ((difference grouped)
     (let* ((grouped? (eq? scenario 'grouped))
            (size (if grouped? 64 128))
            (old-size (quotient size 2))
            (newer (rectangle-cut old? size grouped? #t))
            (older (rectangle-cut old? old-size grouped? #t))
            (count (* (if grouped? 2 1) (- (* size size) (* old-size old-size)))))
       (list ((if old? old-gerbil-ascent-view-difference gerbil-ascent-view-difference)
               newer older count) count)))
    (else
     (let* ((size (case scenario ((small) 4) ((unindexed) 64) (else 1024)))
            (queries (case scenario
                       ((small) '((3 3)))
                       ((absent) (map (lambda (i) (list 9999 i)) (iota 256)))
                       (else (map (lambda (i) (list (modulo i size) (- size 1))) (iota 1024)))))
            (view (rectangle-cut old? size #f (not (eq? scenario 'unindexed)))))
       (list view queries (if (eq? scenario 'absent) 0 (length queries)))))))
(def (ui-consume prepared scenario old?)
  (case scenario
    ((export difference grouped)
     (length ((if old? old-gerbil-ascent-view-rows gerbil-ascent-view-rows) (car prepared))))
    (else
     (length (filter (lambda (row)
       ((if old? old-gerbil-ascent-view-contains? gerbil-ascent-view-contains?) (car prepared) row))
       (cadr prepared))))))
(def (ui-expected prepared scenario)
  ;; Cardinality follows independent Cartesian arithmetic. Check full ordered
  ;; answers against the frozen baseline outside every measured interval.
  (let* ((candidate (ui-prepare #f scenario))
         (expected (if (memq scenario '(export difference grouped)) (cadr prepared) (caddr prepared))))
    (unless (and (= (ui-consume prepared scenario #t) expected)
                 (= (ui-consume candidate scenario #f) expected))
      (error "weighted membership differs from independent Cartesian truth" scenario))
    (when (memq scenario '(export difference grouped))
      (unless (equal? (old-gerbil-ascent-view-rows (car prepared))
                       (gerbil-ascent-view-rows (car candidate)))
        (error "difference descriptor/member order changed" scenario)))
    expected))
