;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-loaded driver A/B: equal files, full hashes, fresh digest per file.
(import :std/encoding/json :std/encoding/hex :std/crypto/digest
        (only-in "../../bindings/artifact" artifact-file-sha256))
(export main)
(def (baseline-file-sha256 path)
  (hex-encode (sha256 (read-file-u8vector path))))
(def (main receipt-path)
  (let* ((receipt (call-with-input-file receipt-path
                   (lambda (port) (read-json port object-as-hash: #t))))
         (resources (hash->list (hash-ref receipt "syntaxResources")))
         (library (path-strip-extension receipt-path))
         (files (cons (cons library (hash-ref receipt "librarySha256"))
                      (map (lambda (entry)
                             (let (resource (cdr entry))
                               (cons (hash-ref resource "path") (hash-ref resource "sha256"))))
                           resources)))
         (samples []))
    (for-each
     (lambda (kind)
       (let* ((digest (if (eq? kind 'baseline) baseline-file-sha256 artifact-file-sha256))
              (start (time->seconds (current-time))))
         (for-each (lambda (file)
                     (unless (equal? (digest (car file)) (cdr file))
                       (error "benchmark resource changed or hash differs" (car file)))) files)
         (set! samples (cons (hash ("kind" (symbol->string kind))
                                  ("seconds" (- (time->seconds (current-time)) start))) samples))))
     '(baseline streaming streaming baseline baseline streaming))
    (display (json->string (hash ("schema" "ascent.build-manifest-hash-benchmark.v1")
                                ("files" (length files))
                                ("bytes" (apply + (map (lambda (file) (file-info-size (file-info (car file)))) files)))
                                ("samples" (reverse samples)))))
    (newline)))
