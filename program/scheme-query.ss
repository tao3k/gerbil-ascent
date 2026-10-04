;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Completed solutions and detached public queries. No engine is constructed here.
(import (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss" GerbilAscentFragmentContract))
(export relational-export relational-query relational-query-name relational-program-query
        make-relational-solution make-relational-program-solution)

(defstruct relational-solution (result))
(defstruct relational-program-solution (result))

;;; Completed results own their relation snapshots. Public queries copy the
;;; row spines so a caller cannot mutate a later query through an old answer.
(def (relational-result-rows result name)
  (unless (.ref result 'finished)
    (error "relational query requires a completed result"))
  (map (lambda (row) (map identity row))
       ((.ref result 'rows-of) name)))

;;; A public label is scoped to its fragment instance, rather than to the
;;; process or composed program. Only declared labels can reveal a handle.
(def (relational-export fragment label)
  (validate GerbilAscentFragmentContract fragment)
  ((.ref fragment 'exports) label))

;;; A query observes only a completed result and a handle exported by the
;;; supplied fragment. Copy returned rows so callers cannot edit the snapshot.
(def (relational-query solution fragment label)
  (unless (relational-solution? solution)
    (error "relational query requires a solved value" solution))
  (let (result (relational-solution-result solution))
    (relational-result-rows result (relational-export fragment label))))

;;; Named one-shot programs may contain private derived relations, so they
;;; cannot use the retained session API, which requires every relation to be
;;; source-capable. Query the completed admitted result directly.
(def (relational-query-name solution name)
  (unless (and (relational-solution? solution) (symbol? name))
    (error "relational named query requires a solved value" name))
  (let (result (relational-solution-result solution))
    (relational-result-rows result name)))

(def (relational-program-query solution name)
  (unless (and (relational-program-solution? solution) (symbol? name))
    (error "relational program query requires a named solution" name))
  (let (result (relational-program-solution-result solution))
    (relational-result-rows result name)))
