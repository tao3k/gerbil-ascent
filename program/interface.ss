;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public rule declaration and evaluation boundary.
(import "types.ss" "objects.ss" "aggregators.ss" "summary.ss" "evaluate.ss"
        "session.ss" "syntax.ss")
(export (import: "types.ss")
        (import: "objects.ss")
        (import: "aggregators.ss")
        (import: "summary.ss")
        gerbil-ascent-evaluate-program
        (import: "session.ss")
        (import: "syntax.ss"))
