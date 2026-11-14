;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :gerbil-ascent/t/performance/uf-reuse/fixture
        :gerbil-ascent/core/relation-view
        (only-in :gerbil-ascent/table/storage gerbil-ascent-trrel-uf-storage-provider
          gerbil-ascent-storage-engine-state gerbil-ascent-storage-initialize-uf!
          gerbil-ascent-storage-admit-state! gerbil-ascent-storage-check-state!
          gerbil-ascent-storage-freeze-view gerbil-ascent-storage-view-extension!))
(import :clan/poo/object :gerbil-ascent/program/func
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-make-engine)
        (prefix-in :gerbil-ascent/t/performance/uf-reuse/reference-evaluate historical-))
(import (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state
          gerbil-ascent-trrel-uf-insert! gerbil-ascent-trrel-uf-count-insert!
          gerbil-ascent-trrel-uf-commit-source-cycle! gerbil-ascent-trrel-uf-freeze
          gerbil-ascent-trrel-uf-observation gerbil-ascent-trrel-uf-validate))
(export ascent-uf-reuse-test)
(import (only-in :gerbil-ascent/program/view-replay gerbil-ascent-small-journal-export))
(def (packed rows)
  (gerbil-ascent-small-journal-export (list (list 'source rows)) car cadr 2000000 0 #f))
(def (field-trace maker)
  (let (seen [])
    (def (field value) (set! seen (cons value seen)) #t)
    (let* ((relation (gerbil-ascent-relation (quote reach) 2 (quote ((0 1) (0 1) (1 2)))
                      gerbil-ascent-hash-index-provider gerbil-ascent-trrel-uf-storage-provider (list field field)))
           (program (gerbil-ascent-program (list relation) [] 16 16 16))
           (_ (set! seen []))
           (engine (maker program #t)))
      (list (reverse seen) ((.ref ((.ref engine (quote .run))) (quote rows-of)) (quote reach))))))
(def ascent-uf-reuse-test
  (test-suite "Interleaved UF admission and bounded replay"
    (test-case "resource planning counts vertices across interleaved injections"
      (let* ((edges (map (lambda (i) (list 0 i)) (iota 64 1)))
             (rows (apply append (make-list 16 edges)))
             (out (packed rows)))
        (check-equal? out (packed edges))
        (check-equal? (length out) 129)))
    (test-case "planning admits 512 vertices and declines the 513th"
      (let (edges (map (lambda (i) (list 0 i)) (iota 511 1)))
        (check-equal? (length (packed edges)) 1023)
        (check-equal? (packed (append edges '((0 512)))) #f)))
    (test-case "group arity and false-valued endpoints retain distinct populations"
      (let (rows '((#f 1) (#f #f 1) (g #f 1) (#f 1) (g #f 1) (#f #f 1)))
        (check-equal? (length (packed rows)) 9)
        (check-equal? (packed rows) (packed '((#f 1) (#f #f 1) (g #f 1))))))
    (test-case "cached injections still charge every source occurrence before failure"
      (let ((owner (gerbil-ascent-storage-engine-state gerbil-ascent-trrel-uf-storage-provider))
            (seen []))
        (check-exception
          (gerbil-ascent-storage-initialize-uf! owner '((0 1) (1 2) (0 1))
            (lambda (row)
              (set! seen (cons row seen))
              (when (= (length seen) 3) (error "source occurrence budget exceeded"))) 0 16) true)
        (check-equal? (reverse seen) '((0 1) (1 2) (0 1)))
        (check-exception (gerbil-ascent-storage-freeze-view owner #f) true)))
    (test-case "all complete engines and controls preserve independent closure"
      (for-each (lambda (scenario)
        (let* ((old (ui-prepare #t scenario)) (new (ui-prepare #f scenario))
               (expected (ui-expected old scenario)))
          (check-equal? (ui-consume old scenario #t) expected)
          (check-equal? (ui-consume new scenario #f) expected)))
        '(initial sparse grouped retained capture cold small packed adjacent large eqrel)))
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
    (test-case "closed source batches match incremental UF order and budget refusal"
      (def (edges width)
        (let (vertices (map (lambda (rank) (- 9001 (* rank 7))) (iota width)))
          (map list vertices (append (cdr vertices) (list (car vertices))))))
      (def (outcome rows limit direct?)
        (let ((owner (gerbil-ascent-storage-engine-state gerbil-ascent-trrel-uf-storage-provider))
              (seen []))
          (let (accepted (with-catch (lambda (_) #f)
                           (lambda ()
                             (gerbil-ascent-storage-initialize-uf! owner rows
                               (lambda (row) (set! seen (cons row seen))) 7 (+ 7 limit) direct?))))
            (if accepted
              (let ()
                (gerbil-ascent-storage-admit-state! owner)
                (let* ((held (gerbil-ascent-storage-freeze-view owner #f))
                       (initial (gerbil-ascent-view-rows held))
                       (frontier (gerbil-ascent-storage-view-extension! owner
                                   (list (caar rows) 'fresh) (+ 1 (length rows)))))
                  (gerbil-ascent-storage-admit-state! owner)
                  (check-equal? (gerbil-ascent-view-rows held) initial)
                  (list accepted (reverse! seen) initial (gerbil-ascent-view-rows frontier))))
              (begin
                (check-exception (gerbil-ascent-storage-freeze-view owner #f) true)
                (list #f (reverse! seen)))))))
      (for-each (lambda (width)
        (let (rows (edges width))
          (for-each (lambda (limit)
            (check-equal? (outcome rows limit #t) (outcome rows limit #f)))
            (iota (+ 1 (* width width)))))) '(2 3 4 7 12))
      (for-each (lambda (width)
        (let ((rows (edges width)) (limit (* width width)))
          (check-equal? (outcome rows limit #t) (outcome rows limit #f))))
        '(63 64 65 384 512)))
    (test-case "direct endpoint aliases survive a second component collapse"
      (for-each
        (lambda (width)
          (let* ((values (iota width))
                 (edges (map list values (append (cdr values) (list (car values)))))
                 (other-values (iota (+ width 1) width))
                 (other-edges (map list other-values
                                (append (cdr other-values) (list (car other-values)))))
                 (direct (gerbil-ascent-trrel-uf-state))
                 (incremental (gerbil-ascent-trrel-uf-state)))
            (gerbil-ascent-trrel-uf-commit-source-cycle! direct (list->vector values))
            (for-each (lambda (row) (gerbil-ascent-trrel-uf-count-insert! incremental row 1000000)) edges)
            (let* ((held (gerbil-ascent-trrel-uf-freeze direct #f))
                   (initial (gerbil-ascent-view-rows held))
                   (first (car values))
                   (last (- width 1)))
              (for-each
                (lambda (row)
                  (check-equal?
                    (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-insert! direct row 1000000))
                    (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-insert! incremental row 1000000)))
                  (check-equal? (gerbil-ascent-trrel-uf-observation direct)
                    (gerbil-ascent-trrel-uf-observation incremental))
                  (check-equal? (gerbil-ascent-trrel-uf-validate direct) #t))
                (append other-edges
                  (list (list last width) (list width first) (list width last)
                        (list first 'new-c) (list 'new-c last))))
              (check-equal? (gerbil-ascent-view-rows held) initial))))
        '(2 3 64 65)))
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
