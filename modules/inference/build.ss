;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o))
(export Build)
(def Build (.o kind: 'module/build roots: '() library-roots: '("applications/finite-flow-program"
                     "applications/polonius"
                     "applications/polonius-paths"
                     "core/binary-program"
                     "program/interface"
                     "rules/interface"
                     "rules/module"
                     "applications/steensgaard"
                     "applications/taint-paths"
                     "applications/scoped-witness"
                     "applications/scoped-reachability-mask"
                     "applications/scoped-composition"
                     "applications/movie-cast-query")))
