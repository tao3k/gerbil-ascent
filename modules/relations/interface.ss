;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def Relations
  identity: 'relations
  core: (.o requires: (.o) scope-contract: ScopeContract
            exports: RelationsAPI
            projections: (list Build))
  features: (.o))
