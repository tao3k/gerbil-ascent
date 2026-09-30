;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public Scheme relational language and lower-level POO declarations.
(import "types.ss" "objects.ss" "aggregators.ss" "summary.ss" "evaluate.ss"
        "session.ss" "scheme-language.ss" "operator.ss")
(export (import: "types.ss")
        (import: "objects.ss")
        (import: "aggregators.ss")
        (import: "summary.ss")
        gerbil-ascent-evaluate-program
        (import: "session.ss")
        (import: "scheme-language.ss")
        (import: "operator.ss"))
