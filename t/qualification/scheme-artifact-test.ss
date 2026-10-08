;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/encoding/json "../native/artifact-admission"
        (only-in :std/crypto/digest sha256) (only-in :std/encoding/hex hex-encode))
(export scheme-artifact-test)
(def (put path text)
  (call-with-output-file [path: path truncate: #t] (lambda (out) (display text out))))
(def (remove-fixture! path)
  (if (eq? (file-type path) 'directory)
    (begin
      (for-each (lambda (name) (remove-fixture! (path-expand name path))) (directory-files [path: path ignore-hidden: 'dot-and-dot-dot]))
      (delete-directory path))
    (delete-file path)))
(def (with-artifact-fixture thunk)
  (let* ((old (current-directory))
         (root (path-expand (string-append ".cache/ascent/tmp/artifact-" (number->string (current-jiffy))) old))
         (token (getenv "ASCENT_DSL_BUILD_TOKEN" #f))
         (started (getenv "ASCENT_DSL_BUILD_STARTED" #f)))
    (artifact-directory! root)
    (try
     (current-directory root)
     (artifact-directory! (path-expand ".cache/ascent/native-library"))
     (for-each (lambda (name) (put name "fixture bytes\n"))
               '("fixture.ss" "justfile"))
     (put ".cache/ascent/native-library/dsl-closure" "fixture executable bytes")
     (setenv "ASCENT_DSL_BUILD_TOKEN" "test-owner")
     (setenv "ASCENT_DSL_BUILD_STARTED" (number->string (- (time->seconds (current-time)) 181)))
     (thunk)
     (finally
      (current-directory old)
      (if token (setenv "ASCENT_DSL_BUILD_TOKEN" token) (setenv "ASCENT_DSL_BUILD_TOKEN"))
      (if started (setenv "ASCENT_DSL_BUILD_STARTED" started) (setenv "ASCENT_DSL_BUILD_STARTED"))
      (remove-fixture! root)))))
(def (stage) (artifact-main "freeze") (artifact-main "bind"))
(def (rejected? thunk)
  (with-catch (lambda (_) #t) (lambda () (thunk) #f)))
(def scheme-artifact-test
  (test-suite "Scheme native artifact publication"
    (test-case "streamed hashes preserve empty binary and buffer-boundary bytes"
      (with-artifact-fixture (lambda ()
        (for-each (lambda (size)
          (let (bytes (make-u8vector size))
            (for-each (lambda (i) (u8vector-set! bytes i (modulo i 256))) (iota size))
            (call-with-output-file [path: "bytes" truncate: #t]
              (lambda (port) (write-subu8vector bytes 0 size port)))
            (check (artifact-digest "bytes") => (hex-encode (sha256 bytes)))))
          '(0 8191 8192 8193 16385 32767 32768 32769 65537)))))
    (test-case "completed build beyond 180 seconds is accepted"
      (with-artifact-fixture (lambda ()
        (stage) (artifact-main "finalize") (artifact-main "check")
        (let (receipt (artifact-read-json ".cache/ascent/native-library/dsl-closure.json"))
          (check (>= (hash-ref receipt "buildElapsedSeconds") 181) => #t)))))
    (test-case "staged failed compiler cannot be accepted"
      (with-artifact-fixture (lambda () (stage) (check (rejected? (lambda () (artifact-main "check"))) => #t))))
    (test-case "other run cannot publish"
      (with-artifact-fixture (lambda ()
        (stage) (setenv "ASCENT_DSL_BUILD_TOKEN" "other-owner")
        (check (rejected? (lambda () (artifact-main "finalize"))) => #t))))
    (test-case "changed source cannot stage or publish"
      (with-artifact-fixture (lambda ()
        (stage) (put "fixture.ss" "changed source")
        (check (rejected? (lambda () (artifact-main "bind"))) => #t)
        (check (rejected? (lambda () (artifact-main "finalize"))) => #t))))
    (test-case "source membership includes hidden directories and rejects additions and deletions"
      (with-artifact-fixture (lambda ()
        (artifact-directory! (path-expand ".source"))
        (put ".source/hidden.ss" "hidden source")
        (check (hash-get (artifact-sources) ".source/hidden.ss") => (artifact-digest ".source/hidden.ss"))
        (stage)
        (put "added.ss" "new source")
        (check (rejected? (lambda () (artifact-main "bind"))) => #t)
        (delete-file "added.ss")
        (stage)
        (delete-file ".source/hidden.ss")
        (check (rejected? (lambda () (artifact-main "finalize"))) => #t))))
    (test-case "changed binary cannot publish or be used"
      (with-artifact-fixture (lambda ()
        (stage) (put ".cache/ascent/native-library/dsl-closure" "changed binary")
        (check (rejected? (lambda () (artifact-main "finalize"))) => #t)
        (stage) (artifact-main "finalize")
        (put ".cache/ascent/native-library/dsl-closure" "changed again")
        (check (rejected? (lambda () (artifact-main "check"))) => #t))))
    (test-case "future build identity cannot freeze"
      (with-artifact-fixture (lambda ()
        (setenv "ASCENT_DSL_BUILD_STARTED" (number->string (+ (time->seconds (current-time)) 1000)))
        (check (rejected? (lambda () (artifact-main "freeze"))) => #t))))))
