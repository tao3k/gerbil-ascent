;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/program/scheme-language relational-program))
(export recursive-declaration recursive-rules)

(def recursive-rules
  '(((path x y) (edge x y))
    ((path x z) (path x y) (path y z))
    ((answer x w) (edge x y) (path y z) (path z w))))

(def (recursive-declaration edges)
  (relational-program
    (relation edge (a b) edges) (relation path (a b)) (relation answer (a b))
    (rule (path ?x ?y) (edge ?x ?y))
    (rule (path ?x ?z) (path ?x ?y) (path ?y ?z))
    (rule (answer ?x ?w) (edge ?x ?y) (path ?y ?z) (path ?z ?w))
    (limits 1000 10000 12000)))
