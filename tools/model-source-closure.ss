;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/compiler/driver :gerbil/expander :std/encoding/json)
(export main)
(def (main . roots)
  (for-each (lambda (root)
    (let* ((context (import-module (string->symbol root)))
           (dependencies (gxc#find-runtime-module-deps context)))
      (displayln "SOURCE-CLOSURE "
       (json->string (hash ("root" root)
                           ("modules" (map (lambda (module) (symbol->string (expander-context-id module)))
                                           (append dependencies (list context)))))))
      (force-output))) roots)
  (displayln "MODULE-OK Scheme compiler source closure")
  (displayln "HARNESS-OK Scheme compiler source closure") (displayln "OK") (force-output))
