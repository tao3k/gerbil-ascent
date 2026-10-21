#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Exercise the production entry with the SDK's actual expansion registry.
(import :gerbil/expander
        (only-in :std/string/misc string-contains)
        (rename-in (only-in "../build.ss" main) (main build-main)))
(export main)
(def (main . arguments)
  (apply build-main arguments)
  (let (loaded (filter (lambda (key)
                        (string-contains (object->string key) "asp-gerbil-scheme"))
                      (hash-keys gx#__module-registry)))
    (unless (null? loaded)
      (error "Production build loaded ASP" loaded))
    (displayln "PRODUCTION-BUILD-NO-ASP contexts=" (hash-length gx#__module-registry))))
