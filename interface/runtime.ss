;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/ffi)
(C-ffi-macrology)

;; This is the linker name emitted for the BuildSpec's libascent target.
(C-declare #<<C
#define ASCENT_LINKER ___LNK_libascent____exe__
/* Use the BuildSpec include path, not Gambit's generated sibling runtime.c. */
#include <runtime.c>
C
)
