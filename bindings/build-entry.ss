#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "../interface/generated-resources.ss"
        (only-in :std/source this-source-file))
(extern namespace: gx eval-syntax)
(export main)

;; Load build declarations through the same generated-resource boundary used
;; by embedded modules. Only build.ss/std/make schedules or compiles tasks.
(def (main . arguments)
  (let (script (path-expand "../build.ss" (path-directory (this-source-file))))
    (ascent-with-generated-resources (lambda ()
      (eval-syntax `(import ,script))
      (apply (eval-syntax 'main #t) arguments)))))
