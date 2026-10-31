;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o) "./func.ss")
(export EvidenceAPI)
;; Publish the existing native procedures; this object does not wrap execution.
(def EvidenceAPI (.o snapshot: reasoning-source-snapshot
          attempt: reasoning-attempt
          inspect: candidate-inspect
          status: reasoning-receipt-status
          rows: reasoning-receipt-rows
          digest: reasoning-receipt-candidate-digest
          capture: candidate-finite-evidence
          verify: candidate-verify-finite-evidence))
