;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o))
(export Build)
(def Build (.o kind: 'module/build roots: '() library-roots: '("candidate/annotations"
                     "candidate/closure"
                     "candidate/stratified-provenance"
                     "candidate/withholding"
                     "interface/request"
                     "interface/engine-api"
                     "candidate/finite-evidence"
                     "candidate/feedback"
                     "candidate/withdrawal-session"
                     "temporal/lens"
                     "temporal/projection"
                     "t/qualification/evidence-api-module")))
