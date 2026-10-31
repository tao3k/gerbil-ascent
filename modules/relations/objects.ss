;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o) "./func.ss")
(export RelationsAPI)
;; Publish the existing native procedures; this object does not wrap execution.
(def RelationsAPI (.o hash-index-provider: gerbil-ascent-hash-index-provider
          set-storage-provider: gerbil-ascent-set-storage-provider))
