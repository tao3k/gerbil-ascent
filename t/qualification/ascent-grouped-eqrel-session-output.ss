;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/t/qualification/ascent-session-corpus
                 ascent-session-qualification)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session)
        (only-in :gerbil-ascent/program/syntax ascent))

(def (make-session left right)
  (gerbil-ascent-open-session
   (ascent
    (relation left (group from to) left)
    (relation right (group from to) right)
    (relation equivalent (group from to) []
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-eqrel-storage-provider))
    (relation equivalent-output (group from to))
    ((equivalent g x y) <-- (left g x y))
    ((equivalent g x y) <-- (right g x y))
    ((equivalent-output g x y) <-- (equivalent g x y))
    (bounds 24 512 1024))))

(ascent-session-qualification main make-session (equivalent-output))
