;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface ascent-fragment))

(export ascent-reach-fragment ascent-generated-seed-fragment)

(def (ascent-reach-fragment edges)
  (ascent-fragment
   (relation edge ((from integer?) (to integer?)) edges)
   (relation closure ((from integer?) (to integer?)))
   ((closure x y) <-- (edge x y))
   ((closure x z) <-- (closure x y) (edge y z))))

(defsyntax (ascent-generated-seed-fragment stx)
  (syntax-case stx ()
    ((_ seed-value)
     (syntax (ascent-fragment
              (relation macro-seed ((value integer?)))
              (fact (macro-seed (lit seed-value))))))))
