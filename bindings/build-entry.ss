#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/source this-source-file))
(extern namespace: gx eval-syntax)
(export main)

;; The upstream interpreter loads the Library-owned build declarations.
(def (main . arguments)
  (let (script (path-expand "../build.ss" (path-directory (this-source-file))))
    (eval-syntax `(import ,script))
    (apply (eval-syntax 'main #t) arguments)))
