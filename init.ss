;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/lang yuanxu!))
(yuanxu!
  :load-modules "."
  mode: explicit
  mount: Library
  (core)
  (table)
  (program)
  (rules)
  (candidate)
  (temporal)
  (interface)
  (applications))
