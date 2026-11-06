;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Private round owner: one node per effective key. Record last-change order
;;; during admission and materialize an independent row spine only at commit.
;;; Joining, type checks and budgets remain with the engine.
(export make-lattice-frontier lattice-frontier-ref lattice-frontier-stage!
        lattice-frontier-rows lattice-frontier-clear!)

(defstruct lattice-round (table changes sequence ordered?) final: #t)
(defstruct lattice-change (row sequence) final: #t)

;;; The factory owns its membership table; callers cannot supply shared buffers.
;; : (forall (k r) (-> (LatticeFrontier k r)))
;; : (-> LatticeFrontier)
(def (make-lattice-frontier)
  (make-lattice-round (make-hash-table) [] 0 #t))

;; : (forall (k r) (-> (LatticeFrontier k r) k (Maybe r)))
;; : (-> LatticeFrontier LatticeKey (Maybe Row))
(def (lattice-frontier-ref (frontier :- lattice-round) key)
  (alet (node (hash-get frontier.table key))
    (using (node :- lattice-change) node.row)))

;;; Return true only for a key's first effective change in this round.
;; : (forall (k r) (-> (LatticeFrontier k r) k r Boolean))
;; : (-> LatticeFrontier LatticeKey Row Boolean)
(def (lattice-frontier-stage! (frontier :- lattice-round) key row)
  (let (sequence frontier.sequence)
    (set! frontier.sequence (+ sequence 1))
    (cond
     ((hash-get frontier.table key)
      => (lambda (node)
           (using (node :- lattice-change)
             (set! node.row row)
             (set! node.sequence sequence))
           (unless (eq? node (car frontier.changes))
             (set! frontier.ordered? #f))
           #f))
     (else
      (let (node (make-lattice-change row sequence))
        (hash-put! frontier.table key node)
        (set! frontier.changes (cons node frontier.changes))
        #t)))))

;;; Unique arrivals already have newest-first order; sort only after a revisit.
;;; Exact sequence numbers have no fixed cutoff or environment-derived limit.
;; : (forall (k r) (-> (LatticeFrontier k r) [r]))
;; : (-> LatticeFrontier [Row])
(def (lattice-frontier-rows (frontier :- lattice-round))
  (map (lambda (node) (using (node :- lattice-change) node.row))
       (if frontier.ordered? frontier.changes
         (list-sort (lambda (a b)
                      (using ((a :- lattice-change) (b :- lattice-change))
                        (> a.sequence b.sequence)))
                    frontier.changes))))

;;; The engine clears only after publishing an independent ordered row spine.
;;; Drop node references and reset ordering before reusing this round owner.
;; : (forall (k r) (-> (LatticeFrontier k r) Void))
;; : (-> LatticeFrontier Void)
(def (lattice-frontier-clear! (frontier :- lattice-round))
  (hash-clear! frontier.table)
  (set! frontier.changes [])
  (set! frontier.sequence 0)
  (set! frontier.ordered? #t))
