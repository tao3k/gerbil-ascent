;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/t/performance/uf-insertion/fixture
        :gerbil-ascent/core/relation-view
        (only-in :gerbil-ascent/table/storage gerbil-ascent-trrel-uf-storage-provider
          gerbil-ascent-storage-engine-state gerbil-ascent-storage-initialize-uf!
          gerbil-ascent-storage-admit-state! gerbil-ascent-storage-check-state!
          gerbil-ascent-storage-freeze-view))
(import :clan/poo/object :gerbil-ascent/program/objects
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/uf-insertion/reference-evaluate historical-))
(import (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state
          gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-count-insert!
          gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-validate))
(export ascent-uf-insertion-test)
(def (field-trace maker)
  (let (seen [])
    (def (field value) (set! seen (cons value seen)) #t)
    (let* ((relation (gerbil-ascent-relation (quote reach) 2 (quote ((0 1) (0 1) (1 2)))
                      gerbil-ascent-hash-index-provider gerbil-ascent-trrel-uf-storage-provider (list field field)))
           (program (gerbil-ascent-program (list relation) [] 16 16 16))
           (_ (set! seen []))
           (engine (maker program #t)))
      (list (reverse seen) ((.ref ((.ref engine (quote .run))) (quote rows-of)) (quote reach))))))
(def ascent-uf-insertion-test
  (test-suite "Initial grouped UF batch ownership"
    (test-case "all complete engines and controls preserve independent closure"
      (for-each (lambda (scenario)
        (let* ((old (ui-prepare #t scenario)) (new (ui-prepare #f scenario))
               (expected (ui-expected old scenario)))
          (check-equal? (ui-consume old scenario #t) expected)
          (check-equal? (ui-consume new scenario #f) expected)))
        '(sparse grouped retained capture cold small packed eqrel)))
    (test-case "count publication preserves all three-node admission histories"
      (let (edges (apply append (map (lambda (a) (map (cut list a <>) (iota 3))) (iota 3))))
        (for-each (lambda (mask)
          (let ((old (gerbil-ascent-trrel-uf-state)) (new (gerbil-ascent-trrel-uf-state)))
            (for-each (lambda (row bit)
              (when (not (= 0 (bitwise-and mask (arithmetic-shift 1 bit))))
                (let* ((frontier (gerbil-ascent-trrel-uf-insert! old row 32))
                       (needed (relation-view-count frontier))
                       (before (gerbil-ascent-trrel-uf-observation new)))
                  (when (> needed 0)
                    (check-exception (gerbil-ascent-trrel-uf-count-insert! new row (- needed 1)) true)
                    (check-equal? (gerbil-ascent-trrel-uf-observation new) before)
                    (check-equal? (gerbil-ascent-trrel-uf-validate new) #t))
                  (check-equal? (gerbil-ascent-trrel-uf-count-insert! new row needed) needed)
                  (check-equal? (gerbil-ascent-trrel-uf-observation new)
                                (gerbil-ascent-trrel-uf-observation old))))) edges (iota 9)))) (iota 512))))
    (test-case "UF external field callbacks retain scalar source and frontier order"
      (let ((old (field-trace historical-gerbil-ascent-make-engine))
            (new (field-trace gerbil-ascent-make-engine)))
        (check-equal? new old)
        (check-equal? (length (car new)) 18)))
    (test-case "batch checks preserve source occurrence order and complete admission"
      (let ((owner (gerbil-ascent-storage-engine-state gerbil-ascent-trrel-uf-storage-provider)) (seen []))
        (check-equal? (gerbil-ascent-storage-initialize-uf! owner '((#f 0 1) (#f 0 1) (g 0 1))
                        (lambda (row) (set! seen (cons row seen))) 2 8) 8)
        (check-equal? (reverse seen) '((#f 0 1) (#f 0 1) (g 0 1)))
        (check-exception (gerbil-ascent-storage-check-state! owner) true)
        (gerbil-ascent-storage-admit-state! owner)
        (check-equal? (relation-view-count (gerbil-ascent-storage-freeze-view owner #f)) 6)))
    (test-case "output and source failures poison the private batch owner"
      (for-each (lambda (source-failure?)
        (let ((owner (gerbil-ascent-storage-engine-state gerbil-ascent-trrel-uf-storage-provider)) (seen []))
          (check-exception
            (gerbil-ascent-storage-initialize-uf! owner '((0 1) (1 2) (2 3))
              (lambda (row) (set! seen (cons row seen))
                (when (and source-failure? (equal? row '(1 2))) (error "source budget exceeded")))
              0 (if source-failure? 16 3)) true)
          (check-equal? (reverse seen) '((0 1) (1 2)))
          (check-exception (gerbil-ascent-storage-freeze-view owner #f) true)
          (check-exception (gerbil-ascent-storage-initialize-uf! owner [] void 0 16) true)))
        (list #f #t)))))
