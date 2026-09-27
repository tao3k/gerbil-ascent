;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 ascent gerbil-ascent-evaluate-program))

(export ascent-fibonacci-example-program
        ascent-fibonacci-example-evaluate
        ascent-context-flow-example-program
        ascent-context-flow-example-evaluate)

(def (ascent-fibonacci-example-program numbers)
  (ascent
    (relation number ((value integer?)) (map list numbers))
    (relation fib ((index integer?) (value integer?)))
    ((fib (lit 0) (lit 1)) <-- (number (lit 0)))
    ((fib (lit 1) (lit 1)) <-- (number (lit 1)))
    ((fib x (expr (y z) (+ y z))) <--
     (number x)
     (if (x) (>= x 2))
     (fib (expr (x) (- x 1)) y)
     (fib (expr (x) (- x 2)) z))
    (bounds 32 64 96)))

(def (ascent-fibonacci-example-evaluate numbers)
  (gerbil-ascent-evaluate-program
   (ascent-fibonacci-example-program numbers)))

(def (ascent-context-flow-example-program edges)
  (ascent
    (relation succ ((from string?) (from-context string?)
                    (to string?) (to-context string?)) edges)
    (relation flow ((from string?) (from-context string?)
                    (to string?) (to-context string?)))
    (relation res ((value string?)))
    ((flow i1 c1 i2 c2) <-- (succ i1 c1 i2 c2))
    ((flow i1 c1 i3 c3) <--
     (flow i1 c1 i2 c2) (flow i2 c2 i3 c3))
    ((res (lit "ok")) <--
     (flow (lit "w1") (lit "c1") (lit "r2") (lit "c1")))
    ((res (lit "err")) <--
     (flow (lit "w1") (lit "c1") (lit "r2") (lit "c2")))
    (bounds 32 256 288)))

(def (ascent-context-flow-example-evaluate edges)
  (gerbil-ascent-evaluate-program
   (ascent-context-flow-example-program edges)))
