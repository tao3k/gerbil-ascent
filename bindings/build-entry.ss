#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/source this-source-file)
        (only-in :gerbil/compiler/base current-or-open-compile-executor
                 compile-executor-output-produced? add-compile-output-job!)
        (only-in :std/list/list-builder with-list-builder)
        (only-in "artifact.ss" artifact-file-sha256))
(extern namespace: gx eval-syntax)
(export main observe-compiler-outputs reuse-compiler-outputs!)

;; The upstream interpreter loads the Library-owned build declarations.
(def (main . arguments)
  (let (script (path-expand "../build.ss" (path-directory (this-source-file))))
    (eval-syntax `(import ,script))
    (apply (eval-syntax 'main #t) arguments)))

;; Observe only outputs registered by the SDK executor. The returned closure
;; is consumed after make drains that executor, never while producers run.
(def (observe-compiler-outputs)
  (let (produced? (compile-executor-output-produced? (current-or-open-compile-executor)))
    (lambda (root)
      (with-list-builder (collect)
        (def (visit path)
          (when (file-exists? path)
            (if (eq? (file-info-type (file-info path #f)) 'directory)
              (for-each (lambda (name) (visit (path-expand name path)))
                        (directory-files path))
              (when (produced? path)
                (collect (cons path (artifact-file-sha256 path)))))))
        (visit (path-expand root))))))

;; Each admission is an SDK output job. Consumers wait for the digest check;
;; a changed or missing output fails the executor before its dependent link.
;; Observations belong only to this build call, not a persistent cache.
(def (reuse-compiler-outputs! outputs)
  (for-each
   (lambda (output)
     (let ((path (car output)) (digest (cdr output)))
       (add-compile-output-job! path
         (lambda ()
           (unless (equal? digest (artifact-file-sha256 path))
             (error "compiler output changed between build phases" path)))
         `(reuse-compiler-output ,path))))
   outputs))
