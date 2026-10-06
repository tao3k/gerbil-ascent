---- MODULE ReadyComponents ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite DAG exploration for component dispatch/complete/drain safety.
\* Component solver correctness and generation publication are separate gates.
EXTENDS Naturals, FiniteSets
CONSTANTS Tasks, Capacity, Mutation
VARIABLES queued, active, done, stopped, returned, badDispatch,
          offered, waiting, merged, snapshot
vars == <<queued, active, done, stopped, returned, badDispatch, offered, waiting, merged, snapshot>>
\* This finite fixture emits one batch and one terminal tail per task.
Pred(task) == IF task = 2 THEN {1} ELSE {}
Facts(tasks) == tasks \X {"batch", "tail"}
Init == /\ queued = Tasks /\ active = {} /\ done = {}
        /\ stopped = FALSE /\ returned = FALSE /\ badDispatch = FALSE
        /\ offered = {} /\ waiting = {} /\ merged = {}
        /\ snapshot = [task \in Tasks |-> {}]
Dispatch(task) ==
  /\ ~stopped /\ ~returned /\ task \in queued /\ Cardinality(active) < Capacity
  /\ (Pred(task) \subseteq done \/ Mutation = "prerequisite")
  /\ badDispatch' = (badDispatch \/ ~ (Pred(task) \subseteq done))
  /\ queued' = queued \ {task} /\ active' = active \cup {task}
  /\ snapshot' = [snapshot EXCEPT ![task] = IF Mutation = "snapshot" THEN {} ELSE merged]
  /\ UNCHANGED <<done, stopped, returned, offered, waiting, merged>>
Offer(task) == /\ ~returned /\ task \in active \ offered
               /\ offered' = offered \cup {task} /\ waiting' = waiting \cup {task}
               /\ UNCHANGED <<queued, active, done, stopped, returned, badDispatch, merged, snapshot>>
Merge(task) == /\ ~returned /\ task \in waiting
               /\ waiting' = waiting \ {task}
               /\ merged' = IF stopped THEN merged ELSE merged \cup {<<task, "batch">>}
               /\ UNCHANGED <<queued, active, done, stopped, returned, badDispatch, offered, snapshot>>
Complete(task) ==
  /\ ~returned /\ task \in active
  /\ ((task \notin waiting /\ (task \in offered \/ stopped)) \/ Mutation = "credit")
  /\ active' = active \ {task} /\ done' = done \cup {task}
  /\ merged' = IF stopped \/ Mutation = "tail" THEN merged ELSE merged \cup {<<task, "tail">>}
  /\ UNCHANGED <<queued, stopped, returned, badDispatch, offered, waiting, snapshot>>
Cancel == /\ ~returned /\ ~stopped /\ stopped' = TRUE
          /\ UNCHANGED <<queued, active, done, returned, badDispatch, offered, waiting, merged, snapshot>>
Return == /\ ~returned
          /\ ((active = {} /\ (stopped \/ queued = {})) \/ Mutation = "early")
          /\ returned' = TRUE
          /\ UNCHANGED <<queued, active, done, stopped, badDispatch, offered, waiting, merged, snapshot>>
Next == Cancel \/ Return \/ (\E task \in Tasks : Dispatch(task) \/ Offer(task) \/ Merge(task) \/ Complete(task))
Spec == Init /\ [][Next]_vars
Partition == /\ queued \cup active \cup done = Tasks
             /\ queued \cap active = {} /\ queued \cap done = {} /\ active \cap done = {}
Prerequisites == ~badDispatch /\ \A task \in active : Pred(task) \subseteq done
CapacityBound == Cardinality(active) <= Capacity
CompleteReturn == returned => active = {} /\ (stopped \/ done = Tasks)
\* A successor snapshot contains all predecessor batches and terminal tails.
DependencySnapshot == \A task \in active \cup done : Facts(Pred(task)) \subseteq snapshot[task]
CompletedDelivery == ~stopped => Facts(done) \subseteq merged
====
