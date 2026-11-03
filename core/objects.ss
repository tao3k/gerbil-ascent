;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import
  (only-in :clan/poo/object .o)
  "func.ss")

(export CoreAPI)

(def CoreAPI
  (.o
    finite-flow: gerbil-ascent-finite-flow
    freeze-masks: gerbil-ascent-freeze-finite-masks
    binary-relation: gerbil-ascent-binary-relation
    binary-copy: gerbil-ascent-binary-copy-rule
    binary-filter: gerbil-ascent-binary-filter-rule
    binary-join: gerbil-ascent-binary-join-rule
    evaluate-binary: gerbil-ascent-evaluate-binary-program
    execution-control: current-ascent-execution-control
    checkpoint!: ascent-execution-checkpoint!
    accept-publication!: ascent-accept-publication!
    with-recovery: ascent-with-recovery))
