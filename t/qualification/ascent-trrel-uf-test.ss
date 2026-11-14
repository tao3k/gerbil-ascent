;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :std/test check-equal? test-case test-suite)
        (only-in :gerbil-ascent/table/trrel-uf gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension
                 gerbil-ascent-trrel-uf-freeze gerbil-ascent-trrel-uf-observation
                 gerbil-ascent-trrel-uf-validate)
        (only-in :gerbil-ascent/core/relation-view gerbil-ascent-view-rows)
        (rename-in (only-in :gerbil-ascent/t/performance/trrel-uf/reference
                           gerbil-ascent-trrel-state gerbil-ascent-trrel-uf-extension)
          (gerbil-ascent-trrel-state old-state) (gerbil-ascent-trrel-uf-extension old-extend)))
(import (rename-in (only-in :gerbil-ascent/t/performance/trrel-uf/root-scan-reference
                           gerbil-ascent-trrel-uf-state gerbil-ascent-trrel-uf-extension)
          (gerbil-ascent-trrel-uf-state scan-state)
          (gerbil-ascent-trrel-uf-extension scan-extend)))
(export ascent-trrel-uf-test)
(def (canonical rows) (list-sort string<? (map object->string rows)))
(def ascent-trrel-uf-test
  (test-suite "SCC union-find matched provider costs"
    (test-case "local predecessor routing preserves frontier order across SCC merges and rejected admission"
      (let ((state (gerbil-ascent-trrel-uf-state)) (before (scan-state))
            (new-rows []) (old-rows []) (held #f) (held-rows #f))
        (for-each (lambda (edge)
          (let ((cut (gerbil-ascent-trrel-uf-freeze state))
                (observation (gerbil-ascent-trrel-uf-observation state)))
            (with-catch (lambda (_) (void))
              (lambda () (gerbil-ascent-trrel-uf-extension state [] [] edge 0)))
            (check-equal? (canonical (gerbil-ascent-view-rows (gerbil-ascent-trrel-uf-freeze state)))
                          (canonical (gerbil-ascent-view-rows cut)))
            (check-equal? (gerbil-ascent-trrel-uf-observation state) observation)
            (check-equal? (gerbil-ascent-trrel-uf-validate state) #t))
          (let ((new (gerbil-ascent-trrel-uf-extension state new-rows [] edge 4096))
                (old (scan-extend before old-rows [] edge 4096)))
            (check-equal? new old)
            (check-equal? (gerbil-ascent-trrel-uf-validate state) #t)
            (set! new-rows (append new new-rows))
            (set! old-rows (append old old-rows)))
          (when held (check-equal? (gerbil-ascent-view-rows held) held-rows))
          (unless held
            (set! held (gerbil-ascent-trrel-uf-freeze state))
            (set! held-rows (gerbil-ascent-view-rows held))))
          (append (map (lambda (i) (list (+ 1000 (* 2 i)) (+ 1001 (* 2 i)))) (iota 40))
          '((0 1) (10 11) (1 2) (20 21) (2 0) (11 12) (12 10)
            (2 10) (21 20) (12 20) (21 1) (30 31) (31 1) (21 30)
            (#f 0 1) (#f 1 2) (#t 10 11) (#f 2 0) (#t 11 10)
            (#f 2 3) (#f 3 1) (1001 1) (21 1000))))
        (check-equal? new-rows old-rows)))
))
