;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-alist-provider)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program
                 gerbil-ascent-open-session
                 gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!
                 gerbil-ascent-session-run))

(export ascent-byods-index-test)

(def (chain group start count)
  (let loop ((node start) (rows []))
    (if (= node (+ start count))
      (reverse rows)
      (loop (+ node 1)
            (cons (list group node (+ node 1)) rows)))))

(def (fixture-program provider)
  (let* ((alpha (chain "alpha" 0 7))
         (beta (chain "beta" 100 3))
         (left (append (take alpha 3) (take beta 1)))
         (right (append (drop alpha 3) (drop beta 1))))
    (ascent
     (relation left (group from to) left)
     (relation right (group from to) right)
     (relation wanted (group node) '(("alpha" 0) ("beta" 100)))
     (relation equivalent (group from to) []
               (index provider)
               (storage gerbil-ascent-eqrel-storage-provider))
     (relation matched (group from to))
     ((equivalent g x y) <-- (left g x y))
     ((equivalent g x y) <-- (right g x y))
     ((matched g x y) <-- (wanted g x) (equivalent g x y))
     (bounds 32 256 256))))

(def (rows result)
  ((.ref result 'rows-of) 'matched))

(def (matched-rows provider)
  (rows (gerbil-ascent-evaluate-program (fixture-program provider))))

(def ascent-byods-index-test
  (test-suite "ASCENT BYODS storage and custom index composition"
    (poo-flow-test-case "grouped eqrel lookup uses custom composite index"
      (let* ((built-columns [])
             (provider
              (ascent-index-alist-provider
               (lambda (columns)
                 (set! built-columns (cons columns built-columns)))))
             (expected
              (append (map (lambda (node) (list "alpha" 0 node)) (iota 8))
                      (map (lambda (node) (list "beta" 100 (+ 100 node)))
                           (iota 4))))
             (hash-rows (matched-rows gerbil-ascent-hash-index-provider))
             (custom-rows (matched-rows provider)))
        (check-equal? (not (not (member '(0 1) built-columns))) #t)
        (check-equal? (length hash-rows) (length expected))
        (check-equal? (length custom-rows) (length expected))
        (for-each
         (lambda (row)
           (check-equal? (not (not (member row hash-rows))) #t)
           (check-equal? (not (not (member row custom-rows))) #t))
         expected)))
    (poo-flow-test-case "custom BYODS index survives append and replacement"
      (let* ((built-columns [])
             (provider
              (ascent-index-alist-provider
               (lambda (columns)
                 (set! built-columns (cons columns built-columns)))))
             (session (gerbil-ascent-open-session (fixture-program provider)))
             (first (gerbil-ascent-session-run session)))
        (check-equal? (length (rows first)) 12)
        (gerbil-ascent-session-append-source!
         session 'right '("beta" 103 104))
        (let (second (gerbil-ascent-session-run session))
          (check-equal? (length (rows second)) 13)
          (check-equal?
           (not (not (member '("beta" 100 104) (rows second)))) #t)
          (gerbil-ascent-session-replace-source!
           session 'left '(("beta" 100 101)))
          (let (third (gerbil-ascent-session-run session))
            (check-equal? (length (rows third)) 5)
            (check-equal?
             (not (not (member '("beta" 100 104) (rows third)))) #t)
            (check-equal? (length (rows first)) 12)
            (check-equal? (length (rows second)) 13)))
        (check-equal? (not (not (member '(0 1) built-columns))) #t)))))
