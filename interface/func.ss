;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The native API owns execution; Module publication introduces no wrappers.
(import "engine-api.ss" "request.ss")
(export (import: "engine-api.ss")
        (import: "request.ss"))
