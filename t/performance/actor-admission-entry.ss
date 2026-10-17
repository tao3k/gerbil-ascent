;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/expander
        (rename-in :gerbil-ascent/t/performance/actor-admission-benchmark (main benchmark-main)))
(export main)
;; One static executable links both kernels and the same callback/measurement code.
(def (main scenario library receipt baseline (side #f))
  (add-load-path! library)
  (benchmark-main scenario library receipt baseline
                  (if side (string-append "allocation-" side) "native-static")
                  (car (command-line))))
