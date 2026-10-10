;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Completed solutions and detached public queries. No engine is constructed here.
(import (only-in :clan/poo/object .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss" GerbilAscentFragmentContract))
(export relational-export relational-prepare-query relational-prepare-queries relational-query relational-query-name relational-program-query
        make-relational-solution make-relational-program-solution)

(defstruct relational-solution (result))
(defstruct relational-program-solution (result))

(def (copy-query-rows rows)
  (map (lambda (row) (map identity row)) rows))

;;; Completed results own their relation snapshots. Public queries copy the
;;; row spines so a caller cannot mutate a later query through an old answer.
(def (relational-result-rows result name)
  (unless (.ref result 'finished)
    (error "relational query requires a completed result"))
  (copy-query-rows ((.ref result 'rows-of) name)))

;;; A public label is scoped to its fragment instance, rather than to the
;;; process or composed program. Only declared labels can reveal a handle.
(def (relational-export fragment label)
  (validate GerbilAscentFragmentContract fragment)
  ((.ref fragment 'exports) label))

(def (checked-solution-result solution)
  (unless (relational-solution? solution)
    (error "relational query requires a solved value" solution))
  (let (result (relational-solution-result solution))
    (unless (.ref result 'finished)
      (error "relational query requires a completed result"))
    result))

;; relational-prepare-query
;;   : (-> Fragment Symbol (-> RelationalSolution Rows))
;;   | doc m%
;;       Resolve one exported handle before repeated completed-snapshot reads.
;;       The retained function copies rows for its supplied solution, never a
;;       captured earlier result. It grants no source mutation authority.
;;
;;       # Examples
;;       ```scheme
;;       (def read-edge (relational-prepare-query fragment 'edge))
;;       (read-edge completed-solution)
;;       ```
;;     %
(def (relational-prepare-query fragment label)
  (let (name (relational-export fragment label))
    (lambda (solution)
      (let (rows-of (.ref (checked-solution-result solution) 'rows-of))
        (copy-query-rows (rows-of name))))))

;; relational-prepare-queries
;;   : (-> Fragment (List Symbol) (-> RelationalSolution (List Rows)))
;;   | doc m%
;;       Prepare an ordered public view without reading any result. Each call
;;       observes one completed solution; duplicate requests return detached
;;       copies and empty requests still require a completed solution.
;;
;;       # Examples
;;       ```scheme
;;       (def read-view (relational-prepare-queries fragment '(path edge path)))
;;       (read-view completed-solution)
;;       ```
;;     %
(def (relational-prepare-queries fragment labels)
  (unless (and (list? labels) (andmap symbol? labels))
    (error "relational query view requires exported labels" labels))
  (validate GerbilAscentFragmentContract fragment)
  (let* ((exports (.ref fragment 'exports))
         (names (map exports labels)))
    (lambda (solution)
      (let* ((result (checked-solution-result solution))
             (rows-of (.ref result 'rows-of)))
        (map (lambda (name) (copy-query-rows (rows-of name))) names)))))

;;; A query observes only a completed result and a handle exported by the
;;; supplied fragment. Copy returned rows so callers cannot edit the snapshot.
(def (relational-query solution fragment label)
  (unless (relational-solution? solution)
    (error "relational query requires a solved value" solution))
  (let (result (relational-solution-result solution))
    (relational-result-rows result (relational-export fragment label))))

;;; Query the completed admitted result directly by its returned handle.
;;; Named retained programs may also contain derived query relations; their
;;; checked mutation authority is restricted to declared source handles.
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
