;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface ascent))

(export ascent-var-points-to-program)

(def (ascent-var-points-to-program assignments allocations loads stores)
  (ascent
   (relation assign ((from string?) (to string?)) assignments)
   (relation new ((variable string?) (object string?)) allocations)
   (relation ld ((target string?) (base string?) (field string?)) loads)
   (relation st ((base string?) (field string?) (value string?)) stores)
   (relation alias ((from string?) (to string?)))
   (relation points-to ((variable string?) (object string?)))
   ((alias x x) <-- (assign x _))
   ((alias x x) <-- (assign _ x))
   ((alias x y) <-- (assign x y))
   ((alias x y) <-- (ld x a f) (alias a b) (st b f y))
   ((points-to x y) <-- (new x y))
   ((points-to x y) <-- (alias x z) (points-to z y))
   (bounds 64 256 320)))
