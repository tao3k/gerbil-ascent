;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil-ascent/program/interface
                 gerbil-ascent-relation gerbil-ascent-variable
                 gerbil-ascent-atom gerbil-ascent-rule
                 gerbil-ascent-program gerbil-ascent-evaluate-program))

(export ascent-typed-program-evaluate)

(def (ascent-typed-program-evaluate enabled? input)
  (let ((flag (gerbil-ascent-variable 'flag))
        (name (gerbil-ascent-variable 'name)))
    (gerbil-ascent-evaluate-program
     (gerbil-ascent-program
      (list (gerbil-ascent-relation 'enabled 0 (if enabled? '(()) []))
            (gerbil-ascent-relation 'input 2 input)
            (gerbil-ascent-relation 'selected 2 []))
      (list
       (gerbil-ascent-rule
        (list (gerbil-ascent-atom 'selected (list flag name)))
        (list (gerbil-ascent-atom 'enabled [])
              (gerbil-ascent-atom 'input (list flag name)))))
      32 32 64))))
