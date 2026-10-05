---- MODULE ReadyComponents ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite DAG exploration for component dispatch/complete/drain safety.
\* Component solver correctness and generation publication are separate gates.
EXTENDS Naturals, FiniteSets
CONSTANTS Tasks, Capacity, Mutation
VARIABLES queued, active, done, stopped, returned, badDispatch
vars == <<queued, active, done, stopped, returned, badDispatch>>
Pred(task) == IF task = 2 THEN {1} ELSE {}
Init == /\ queued = Tasks /\ active = {} /\ done = {}
        /\ stopped = FALSE /\ returned = FALSE /\ badDispatch = FALSE
Dispatch(task) ==
  /\ ~stopped /\ ~returned /\ task \in queued /\ Cardinality(active) < Capacity
  /\ (Pred(task) \subseteq done \/ Mutation = "prerequisite")
  /\ badDispatch' = (badDispatch \/ ~ (Pred(task) \subseteq done))
  /\ queued' = queued \ {task} /\ active' = active \cup {task}
  /\ UNCHANGED <<done, stopped, returned>>
Complete(task) ==
  /\ ~returned /\ task \in active
  /\ active' = active \ {task} /\ done' = done \cup {task}
  /\ UNCHANGED <<queued, stopped, returned, badDispatch>>
Cancel == /\ ~returned /\ ~stopped /\ stopped' = TRUE
          /\ UNCHANGED <<queued, active, done, returned, badDispatch>>
Return == /\ ~returned
          /\ ((active = {} /\ (stopped \/ queued = {})) \/ Mutation = "early")
          /\ returned' = TRUE
          /\ UNCHANGED <<queued, active, done, stopped, badDispatch>>
Next == Cancel \/ Return \/ (\E task \in Tasks : Dispatch(task) \/ Complete(task))
Spec == Init /\ [][Next]_vars
Partition == /\ queued \cup active \cup done = Tasks
             /\ queued \cap active = {} /\ queued \cap done = {} /\ active \cap done = {}
Prerequisites == ~badDispatch /\ \A task \in active : Pred(task) \subseteq done
CapacityBound == Cardinality(active) <= Capacity
CompleteReturn == returned => active = {} /\ (stopped \/ done = Tasks)
====
