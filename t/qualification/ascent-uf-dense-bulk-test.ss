;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/core/relation-view
        :gerbil-ascent/table/trrel-uf
        (prefix-in :gerbil-ascent/t/performance/uf-dense-bulk/reference-trrel-uf old-))
(export ascent-uf-dense-bulk-test)
(def (rows state)
  (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-freeze state #f)))
(def (check-members actual expected)
  (let (seen (list->hash-table (map (cut cons <> #t) actual)))
    (check-equal? (length actual) (length expected))
    (check-equal? (hash-length seen) (length expected))
    (check-equal? (andmap (cut hash-get seen <>) expected) #t)))
(def (exercise input)
  (let ((old (old-gerbil-ascent-trrel-uf-state))
        (new (gerbil-ascent-trrel-uf-state)))
    (for-each (lambda (row)
      (let ((expected (old-gerbil-ascent-trrel-uf-count-insert! old row 2000000)))
        (check-equal? (gerbil-ascent-trrel-uf-count-insert! new row 2000000) expected))) input)
    (check-equal? (gerbil-ascent-trrel-uf-validate new) #t)
    (check-equal? (gerbil-ascent-trrel-uf-observation new)
                  (old-gerbil-ascent-trrel-uf-observation old))
    (check-members (rows new)
      (gerbil-ascent-view-rows (old-gerbil-ascent-trrel-uf-freeze old #f)))))
(def ascent-uf-dense-bulk-test
  (test-suite "admitted dense UF axis ownership"
    (test-case "both fresh directions and SCC retirement preserve closure"
      (for-each exercise
        (list (append (map (lambda (i) (list i (+ i 1))) (iota 96))
                      '((96 40) (97 0) (96 97)))
              (append (map (lambda (i) (list (+ i 1) i)) (iota 96))
                      '((40 96) (0 97) (97 96)))
              (append (map (lambda (i) (list 7 i (+ i 1))) (iota 96))
                      '((8 0 1) (7 96 40) (7 97 0) (7 96 97))))))
    (test-case "rejection leaves storage and captured cuts unchanged"
      (let ((state (gerbil-ascent-trrel-uf-state)))
        (for-each (lambda (i)
          (gerbil-ascent-trrel-uf-count-insert! state (list i (+ i 1)) 2000000)) (iota 96))
        (let* ((cut (gerbil-ascent-trrel-uf-freeze state #f))
               (saved (gerbil-ascent-view-rows cut))
               (physical (gerbil-ascent-trrel-uf-resource-observation state)))
          ;; Each direction creates one diagonal and 97 off-diagonal facts.
          (for-each (lambda (row)
            (check-exception (gerbil-ascent-trrel-uf-count-insert! state row 97) true)
            (check-equal? (gerbil-ascent-trrel-uf-resource-observation state) physical)
            (check-members (rows state) saved)) '((96 97) (98 0)))
          (check-equal? (gerbil-ascent-trrel-uf-count-insert! state '(96 97) 98) 98)
          (gerbil-ascent-trrel-uf-count-insert! state '(97 0) 2000000)
          (check-equal? (gerbil-ascent-view-rows cut) saved)
          (check-equal? (gerbil-ascent-trrel-uf-validate state) #t))))
    (test-case "sparse historical births do not force dense remote copies"
      (exercise
        (append (map (lambda (i) (list (+ i 1) i)) (iota 48))
                (map (lambda (i) (list i (+ i 1))) (iota 160 1000))
                '((1160 1000) (1160 0) (2000 1160) (48 2000)))))))
