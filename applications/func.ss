;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The native API owns execution; Module publication introduces no wrappers.

(import
  "finite-flow-program.ss"
  "polonius.ss"
  "polonius-paths.ss"
  "steensgaard.ss"
  "taint-paths.ss"
  "scoped-witness.ss"
  "scoped-reachability-mask.ss"
  "scoped-composition.ss"
  "movie-cast-query.ss")

(export
  (import: "finite-flow-program.ss")
  (import: "polonius.ss")
  (import: "polonius-paths.ss")
  (import: "steensgaard.ss")
  (import: "taint-paths.ss")
  (import: "scoped-witness.ss")
  (import: "scoped-reachability-mask.ss")
  (import: "scoped-composition.ss")
  (import: "movie-cast-query.ss"))
