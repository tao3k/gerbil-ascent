;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o) "func.ss")
(export ApplicationsAPI)
(def ApplicationsAPI
  (.o finite-flow: gerbil-ascent-finite-flow-program
         polonius: gerbil-ascent-polonius-program
         polonius-paths: gerbil-ascent-polonius-path-flows
         steensgaard: gerbil-ascent-steensgaard-program
         taint-paths: gerbil-ascent-taint-path-program
         scoped-witness: gerbil-ascent-scoped-witness-program
         branch-scoped-witness: gerbil-ascent-branch-scoped-witness-program
         scoped-mask: gerbil-ascent-scoped-reachability-mask-program
         bounded-scoped-mask: gerbil-ascent-bounded-scoped-reachability-mask-program
         scoped-composition: gerbil-ascent-scoped-composition-program
         compose-scoped: gerbil-ascent-compose-scoped-program
         scoped-query: gerbil-ascent-scoped-query-program
         movie-cast: gerbil-ascent-movie-cast-program))
