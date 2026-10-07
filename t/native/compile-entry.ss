;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A fresh compiler owns only the generated entry and its imported closure.
;;; Library-make analysis cannot survive across this process boundary.
(import (only-in :gerbil/compiler compile-module compile-exe execute-pending-compile-jobs!)
        (only-in :gerbil/runtime/loader add-load-path!)
        (only-in "artifact-admission.ss" artifact-digest))
(export main)

;; : (-> Path LibraryPath BinaryPath Void)
(def (main source library binary)
  (displayln "NATIVE-ENTRY-COMPILER " source)
  (force-output)
  (add-load-path! library)
  (let ((generated (artifact-digest source))
        (options [output-dir: library output-file: binary
                  parallel: #t verbose: #t invoke-gsc: #t static: #t]))
    (compile-module source [invoke-gsc: #f options ...])
    (compile-exe source options)
    (execute-pending-compile-jobs!)
    (unless (equal? generated (artifact-digest source))
      (error "generated native test entry changed during compilation"))))
