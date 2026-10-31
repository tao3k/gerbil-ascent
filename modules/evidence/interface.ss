;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def Evidence
  identity: 'evidence
  core: (.o requires: (.o) scope-contract: ScopeContract
            exports: EvidenceAPI
            projections: (list Build))
  features: (.o))
