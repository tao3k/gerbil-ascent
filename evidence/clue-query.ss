;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil-ascent/evidence/interface)
(export make-clue-query-evidence)

;; The same declaration is loaded by the Rust Evidence runtime.
(include "../python/src/ascent/clue_query_rules.ss")
