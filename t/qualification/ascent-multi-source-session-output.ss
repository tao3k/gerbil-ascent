;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/t/qualification/ascent-session-corpus
                 ascent-session-qualification)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-count gerbil-ascent-open-session)
        (only-in :gerbil-ascent/program/syntax ascent))

(def (make-session edges blocked)
  (gerbil-ascent-open-session
   (ascent
    (relation edge (from to) edges)
    (relation blocked (from to) blocked)
    (relation reach (from to))
    (relation allowed (from to))
    (relation total (value))
    ((reach x y) <-- (edge x y))
    ((reach x z) <-- (reach x y) (edge y z))
    ((allowed x y) <-- (reach x y) (not (blocked x y)))
    ((total n) <--
     (aggregate n gerbil-ascent-count () (allowed _ _)))
    (bounds 12 100 100))))

(ascent-session-qualification
 main make-session (reach allowed total))
