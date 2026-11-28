;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .get)
        (only-in "../../interface/build.ss" Build gerbil-ascent-compiler-options))
(export compiler-profile-test)

(def compiler-profile-test
  (test-suite "Module compiler profile"
    (test-case "prepare preserves caller flags and remains idempotent"
      (def name "CORCXXFLAGS_GAMBUILD")
      (def previous (getenv name #f))
      (def expected (string-append "-O1 -DASCENT_CALLER_FLAG=1 "
                       (cadr gerbil-ascent-compiler-options)))
      (dynamic-wind
        (lambda () (setenv name "-O1 -DASCENT_CALLER_FLAG=1"))
        (lambda ()
          ((.get Build .prepare) '())
          (check-equal? (getenv name) expected)
          ((.get Build .prepare) '())
          (check-equal? (getenv name) expected))
        (lambda () (if previous (setenv name previous) (setenv name)))))))
