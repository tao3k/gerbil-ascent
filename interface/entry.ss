;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import "c-api.ss" "runtime.ss")
(export main)

;; The Gerbil executable driver owns the linked runtime initialization.
;; Embedded C ABI callers enter through ascent_runtime_init, not this stub.
(def (main . args) (void))
