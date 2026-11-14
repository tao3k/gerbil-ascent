;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in "../harness/artifact-admission"
                 artifact-main artifact-read-json artifact-digest artifact-directory! artifact-sources))
(export scheme-artifact-test)

(def binary ".cache/ascent/compiled-library/dsl-closure")
(def (put path text)
  (call-with-output-file [path: path truncate: #t]
    (lambda (port) (display text port))))

(def (with-artifact-fixture thunk)
  (call-with-temporary-directory "ascent-artifact-"
    (lambda (root)
      (let ((old (current-directory))
            (token (getenv "ASCENT_DSL_BUILD_TOKEN" #f))
            (started (getenv "ASCENT_DSL_BUILD_STARTED" #f)))
        (try
         (current-directory root)
         (artifact-directory! (path-expand ".cache/ascent/compiled-library"))
         (put "fixture.ss" "fixture bytes\n")
         (put "justfile" "fixture bytes\n")
         (put binary "fixture executable bytes")
         (setenv "ASCENT_DSL_BUILD_TOKEN" "test-owner")
         (setenv "ASCENT_DSL_BUILD_STARTED"
                 (number->string (- (time->seconds (current-time)) 181)))
         (thunk)
         (finally
          (current-directory old)
          (if token (setenv "ASCENT_DSL_BUILD_TOKEN" token) (setenv "ASCENT_DSL_BUILD_TOKEN"))
          (if started (setenv "ASCENT_DSL_BUILD_STARTED" started) (setenv "ASCENT_DSL_BUILD_STARTED"))))))))

(def (stage)
  (artifact-main "freeze")
  (artifact-main "bind"))

(def (rejected? thunk)
  (with-catch (lambda (_) #t) (lambda () (thunk) #f)))

(def scheme-artifact-test
  (test-suite "Scheme native artifact publication"
    (test-case "completed build beyond 180 seconds is accepted"
      (with-artifact-fixture (lambda ()
        (stage) (artifact-main "finalize") (artifact-main "check")
        (let (receipt (artifact-read-json ".cache/ascent/compiled-library/dsl-closure.json"))
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
        (stage) (put binary "changed binary")
        (check (rejected? (lambda () (artifact-main "finalize"))) => #t)
        (stage) (artifact-main "finalize")
        (put binary "changed again")
        (check (rejected? (lambda () (artifact-main "check"))) => #t))))
    (test-case "future build identity cannot freeze"
      (with-artifact-fixture (lambda ()
        (setenv "ASCENT_DSL_BUILD_STARTED" (number->string (+ (time->seconds (current-time)) 1000)))
        (check (rejected? (lambda () (artifact-main "freeze"))) => #t))))))
