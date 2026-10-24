;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/t/qualification/ascent-session-corpus
                 ascent-session-qualification)
        (only-in :gerbil-ascent/table/interface
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-eqrel-storage-provider
                 gerbil-ascent-trrel-storage-provider
                 gerbil-ascent-trrel-uf-storage-provider)
        (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-open-session)
        (only-in :gerbil-ascent/program/syntax ascent))

(def (make-session left right)
  (gerbil-ascent-open-session
   (ascent
    (relation left (from to) left)
    (relation right (from to) right)
    (relation equivalent (from to) []
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-eqrel-storage-provider))
    (relation strict (from to) []
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-trrel-storage-provider))
    (relation reflexive (from to) []
              (index gerbil-ascent-hash-index-provider)
              (storage gerbil-ascent-trrel-uf-storage-provider))
    (relation strict-output (from to))
    (relation reflexive-output (from to))
    (relation equivalent-output (from to))
    ((equivalent x y) <-- (left x y))
    ((equivalent x y) <-- (right x y))
    ((strict x y) <-- (left x y))
    ((strict x y) <-- (right x y))
    ((reflexive x y) <-- (left x y))
    ((reflexive x y) <-- (right x y))
    ((strict-output x y) <-- (strict x y))
    ((reflexive-output x y) <-- (reflexive x y))
    ((equivalent-output x y) <-- (equivalent x y))
    (bounds 16 128 256))))

(ascent-session-qualification
 main make-session (strict-output reflexive-output equivalent-output))
