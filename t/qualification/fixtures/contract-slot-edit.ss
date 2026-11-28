;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref .slot? .putslot! $constant-slot-spec))

;; Keep the nominal prototype and field descriptors stable while replacing a
;; protocol method. A supported slot edit invalidates their materialized values.
(def (ascent-replace-contract-slot! contract slot value)
  (let (declarations
        (filter-map (lambda (name)
                      (and (.slot? contract name) (cons name (.ref contract name))))
                    '(proto responsibilities)))
    (for-each (lambda (entry)
                (.putslot! contract (car entry) ($constant-slot-spec (cdr entry))))
              declarations)
    (.putslot! contract slot ($constant-slot-spec value))))
