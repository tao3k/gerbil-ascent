;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-program gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule gerbil-ascent-guard)
        (only-in :gerbil-ascent/program/evaluate
                 gerbil-ascent-evaluate-program gerbil-ascent-make-engine)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-set-storage-provider)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-hash-index-provider)
        (only-in :gerbil-ascent/t/qualification/ascent-workspace-reference-evaluate
                 ascent-workspace-reference-evaluate-program
                 ascent-workspace-reference-make-engine))
(export ascent-workspace-test)

(def (rows result name) ((.ref result 'rows-of) name))
(def (chain edges (storage gerbil-ascent-set-storage-provider) (guarded? #f))
  (let* ((x (gerbil-ascent-variable 'x)) (y (gerbil-ascent-variable 'y))
         (body (list (gerbil-ascent-atom 'reach (list x))
                     (gerbil-ascent-atom 'edge (list x y)))))
    (gerbil-ascent-program
     (list (gerbil-ascent-relation 'edge 2 edges)
           (gerbil-ascent-relation 'reach 1 '((0)) gerbil-ascent-hash-index-provider storage)
           (gerbil-ascent-relation 'copy 1 []))
     (list (gerbil-ascent-rule
            ;; Duplicate heads exercise pending deduplication on every round.
            (list (gerbil-ascent-atom 'reach (list y))
                  (gerbil-ascent-atom 'reach (list y))
                  (gerbil-ascent-atom 'copy (list y)))
            (if guarded? (append body (list (gerbil-ascent-guard '(y) guarded?))) body)))
     256 512 768)))
(def (edges width) (map (lambda (n) (list n (+ n 1))) (iota width)))

(def ascent-workspace-test
  (test-suite "Complete fixed-point workspace lifetime"
    (poo-flow-test-case "retained timeout append replacement cycles preserve old snapshots"
      (let* ((p (chain []))
             (old (ascent-workspace-reference-make-engine p #t))
             (new (gerbil-ascent-make-engine p #t))
             (old-first ((.ref old '.run))) (new-first ((.ref new '.run))))
        (for-each
         (lambda (cycle)
           (let* ((width (+ 16 cycle)) (source (edges width)))
             (for-each
              (lambda (engine)
                ((.ref engine '.replace-source!) 'edge
                  (if (even? cycle) source (reverse source)))
                ((.ref engine '.run-timeout) 0))
              (list old new))
             (let ((left ((.ref old '.run))) (right ((.ref new '.run))))
               (check-equal? (rows right 'reach) (map list (iota (+ width 1))))
               (check-equal? (rows right 'copy) (rows left 'copy)))
             (for-each
              (lambda (engine)
                ((.ref engine '.append-source!) 'edge '(0 1))
                ((.ref engine '.append-source!) 'edge (list width (+ width 1)))
                ((.ref engine '.run-timeout) 0)) (list old new))
             (let ((left ((.ref old '.run))) (right ((.ref new '.run))))
               (check-equal? (rows right 'reach) (rows left 'reach))
               (check-equal? (rows right 'reach) (map list (iota (+ width 2))))
               (check-equal? (rows right 'copy) (rows left 'copy)))
             (check-equal? (rows old-first 'reach) '((0)))
             (check-equal? (rows new-first 'reach) '((0)))))
         (iota 16))))
    (poo-flow-test-case "custom storage retains exact all and pending row spines across rounds"
      (let* ((calls [])
             (storage (.o (:: @ gerbil-ascent-set-storage-provider)
                          (.extend-rows
                           (lambda (_ all pending row budget)
                             (set! calls (cons (list all pending row budget) calls))
                             (list row)))))
             (p (chain (edges 64) storage))
             (old (ascent-workspace-reference-evaluate-program p))
             (old-calls calls))
        (set! calls [])
        (let ((new (gerbil-ascent-evaluate-program p)))
          (check-equal? calls old-calls)
          (check-equal? (rows new 'reach) (map list (iota 65)))
          (check-equal? (rows new 'copy) (rows old 'copy)))))
    (poo-flow-test-case "generic callback rules reuse rounds with exact invocation order"
      (for-each
       (lambda (width)
         (let* ((calls [])
                (p (chain (edges width) gerbil-ascent-set-storage-provider
                          (lambda (value) (set! calls (cons value calls)) #t)))
                (old (ascent-workspace-reference-evaluate-program p))
                (old-calls calls))
           (set! calls [])
           (let (new (gerbil-ascent-evaluate-program p))
             (check-equal? calls old-calls)
             (check-equal? (rows new 'reach) (map list (iota (+ width 1))))
             (check-equal? (rows new 'copy) (rows old 'copy)))))
       '(0 1 16 64)))))
