;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; IRIS section 3.1 transfer over caller-supplied finite graph/specifications.
;;; No Java extraction, CodeQL integration, LLM labeling or vulnerability verdict.
(import :gerbil-ascent/program/objects)
(export gerbil-ascent-taint-path-program)
(def (gerbil-ascent-taint-path-program edges sources sinks sanitizers
        (input-budget 10000) (fact-budget 10000) (output-budget 20000))
  (let ((s (gerbil-ascent-variable 's)) (x (gerbil-ascent-variable 'x))
        (y (gerbil-ascent-variable 'y)))
    (def (a name . terms) (gerbil-ascent-atom name terms))
    (def (clean point) (gerbil-ascent-negation 'taint_sanitizer (list point)))
    (gerbil-ascent-program
      (list (gerbil-ascent-relation 'taint_edge 2 edges)
            (gerbil-ascent-relation 'taint_source 1 sources)
            (gerbil-ascent-relation 'taint_sink 1 sinks)
            (gerbil-ascent-relation 'taint_sanitizer 1 sanitizers)
            (gerbil-ascent-relation 'taint_path 2 [])
            (gerbil-ascent-relation 'taint_alert 2 []))
      (list
        (gerbil-ascent-rule (list (a 'taint_path s s))
          (list (a 'taint_source s) (clean s)))
        (gerbil-ascent-rule (list (a 'taint_path s y))
          (list (a 'taint_path s x) (a 'taint_edge x y) (clean y)))
        (gerbil-ascent-rule (list (a 'taint_alert s y))
          (list (a 'taint_path s y) (a 'taint_sink y))))
      input-budget fact-budget output-budget)))
