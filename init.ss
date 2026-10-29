;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :yuanxu/module-system/selection/init-syntax yuanxu!))
;; Production capabilities own native roots; Core derives their source closure.
(yuanxu!
  :load-modules "./modules" mode: explicit rename: Library
  (relations) (inference) (evidence))
