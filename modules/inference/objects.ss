;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o) "./func.ss")
(export InferenceAPI)
;; Publish the existing native procedures; this object does not wrap execution.
(def InferenceAPI (.o relation: gerbil-ascent-relation
          program: gerbil-ascent-program
          evaluate: gerbil-ascent-evaluate-program
          open-session: gerbil-ascent-open-session))
