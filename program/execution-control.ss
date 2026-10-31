;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Optional host admission checks. The default Scheme runtime pays no FFI cost.
(export current-ascent-execution-control ascent-execution-checkpoint! ascent-accept-publication! ascent-with-recovery)
(def current-ascent-execution-control (make-parameter #f))
(def (ascent-execution-checkpoint! (work 0) (facts 0))
  (let (check (current-ascent-execution-control))
    (when check (check work facts))))

;; The final acceptance check is the transaction's linearization point. Later
;; interrupts cannot convert a committed replacement into a canceled return.
(def (ascent-accept-publication!) (ascent-execution-checkpoint! -1 0))
(def (ascent-with-recovery thunk)
  (let (check (current-ascent-execution-control))
    (dynamic-wind
      (lambda () (when check (check -2 0)))
      (lambda () (parameterize ((current-ascent-execution-control #f)) (thunk)))
      (lambda () (when check (check -3 0))))))
