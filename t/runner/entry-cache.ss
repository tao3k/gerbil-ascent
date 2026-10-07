;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; One admitted executable per entry mode. Cache misses always rebuild; test results
;;; are never cached. The lane lock in main.ss owns this receipt and binary.
(import :std/encoding/json :std/misc/process
        (only-in :gerbil/runtime/system gerbil-home)
        (only-in "artifact-admission.ss" artifact-digest artifact-sources
          artifact-read-json artifact-matching-sources?))
(export entry-inputs entry-current? bind-entry!)
(def (generated? path)
  (or (string-contains path "__single-test.") (string-contains path "/single-test.")
      (string-contains path "__test-pool.") (string-contains path "/test-pool.")
      (string-contains path "__single-test~") (string-contains path "/single-test~")
      (string-contains path "__test-pool~") (string-contains path "/test-pool~")))
;; : (-> LibraryPath Boolean InputDigests)
(def (entry-inputs library (objects? #t))
  (let* ((result (artifact-sources)) (home (gerbil-home))
         (prefix (path-expand (getenv "GERBIL_PATH" "~/.gerbil")))
         (paths (string-split
           (run-process ["rg" "--files" "--hidden" "--no-ignore" "-L" "-0"
                         library (path-expand "lib" prefix) (path-expand "lib" home)]) #\nul)))
    (for-each (lambda (path)
      (when (and (not (generated? path))
                 (ormap (lambda (suffix) (string-suffix? suffix path))
                   (if objects?
                     '(".o" ".scm" ".ssi" ".ssxi" ".a" ".so" ".dylib")
                     '(".scm" ".ssi" ".a" ".so" ".dylib"))))
        (hash-put! result path (artifact-digest path)))) paths)
    (for-each (lambda (name)
      (hash-put! result (string-append "env:" name) (getenv name "")))
      '("GERBIL_HOME" "GERBIL_PATH" "GERBIL_LOADPATH" "GERBIL_PREFIX" "GAMBOPT"
        "PATH" "CC" "CXX" "CFLAGS" "CPPFLAGS" "LDFLAGS" "LIBRARY_PATH"
        "CPATH" "SDKROOT" "DEVELOPER_DIR"))
    (for-each (lambda (name)
      (let (path (car (string-split (run-process ["which" name]) #\newline)))
        (hash-put! result (string-append "tool:" name) path)
        (hash-put! result path (artifact-digest path)))) '("gxi" "gsc" "gcc"))
    result))
;; : (-> ReceiptPath BinaryPath GeneratedDigest InputDigests String Boolean)
(def (entry-current? receipt binary generated inputs (key ""))
  (and (file-exists? receipt) (file-exists? binary)
    (with-catch (lambda (_) #f)
      (lambda ()
        (let (record (artifact-read-json receipt))
          (and (equal? (hash-get record "schema") "ascent.native-test-entry")
               (equal? (hash-get record "version") 1)
               (equal? (hash-get record "compilerExitStatus") 0)
               (equal? (hash-get record "requestedKey") key)
               (equal? (hash-get record "generatedSha256") generated)
               (equal? (hash-get record "binarySha256") (artifact-digest binary))
               (artifact-matching-sources? inputs (hash-ref record "inputs"))))))))
;; : (-> ReceiptPath BinaryPath GeneratedDigest InputDigests String Void)
(def (bind-entry! receipt binary generated inputs (key ""))
  (let (staging (string-append receipt ".pending"))
    (call-with-output-file [path: staging truncate: #t]
      (lambda (out)
        (display (json->string
          (hash ("schema" "ascent.native-test-entry") ("version" 1)
                ("compilerExitStatus" 0) ("requestedKey" key) ("generatedSha256" generated)
                ("binarySha256" (artifact-digest binary)) ("inputs" inputs))) out)
        (newline out)))
    (rename-file staging receipt #t)))
