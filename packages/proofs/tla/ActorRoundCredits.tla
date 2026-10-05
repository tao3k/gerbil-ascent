---- MODULE ActorRoundCredits ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Safety abstraction of native streaming batches, credit and drain. Finite
\* task inventory is TLC exploration, not a runtime generation restriction.
EXTENDS Naturals, FiniteSets
CONSTANTS Tasks, Capacity, EarlyReturn
VARIABLES queued, active, waiting, terminal, stopped, returned
vars == <<queued, active, waiting, terminal, stopped, returned>>
Init == /\ queued = Tasks /\ active = {} /\ waiting = {} /\ terminal = {}
        /\ stopped = FALSE /\ returned = FALSE
Dispatch(t) == /\ ~stopped /\ ~returned /\ t \in queued
               /\ Cardinality(active) < Capacity
               /\ queued' = queued \ {t} /\ active' = active \cup {t}
               /\ UNCHANGED <<waiting, terminal, stopped, returned>>
Offer(t) == /\ ~returned /\ t \in active \ waiting
            /\ waiting' = waiting \cup {t}
            /\ UNCHANGED <<queued, active, terminal, stopped, returned>>
Credit(t) == /\ t \in waiting /\ ~returned
             /\ waiting' = waiting \ {t}
             /\ UNCHANGED <<queued, active, terminal, stopped, returned>>
\* Stop refuses merge and returns stop credit. A task remains assigned until
\* its completion is observed; an empty queue is insufficient. In the native
\* pool, task completion precedes worker reuse. Joining the pool at round exit
\* is a separate lifecycle obligation, checked by native tests, not this model.
Stop == /\ ~returned /\ ~stopped /\ stopped' = TRUE
        /\ UNCHANGED <<queued, active, waiting, terminal, returned>>
Finish(t) == /\ t \in active \ waiting /\ ~returned
             /\ active' = active \ {t} /\ terminal' = terminal \cup {t}
             /\ UNCHANGED <<queued, waiting, stopped, returned>>
Return == /\ ~returned
          /\ (EarlyReturn \/ (active = {} /\ (stopped \/ queued = {})))
          /\ returned' = TRUE
          /\ UNCHANGED <<queued, active, waiting, terminal, stopped>>
Next == Stop \/ Return \/ (\E t \in Tasks : Dispatch(t) \/ Offer(t) \/ Credit(t) \/ Finish(t))
Spec == Init /\ [][Next]_vars
Partition == /\ queued \cup active \cup terminal = Tasks
             /\ queued \cap active = {} /\ queued \cap terminal = {}
             /\ active \cap terminal = {}
BoundedCredit == waiting \subseteq active /\ Cardinality(waiting) <= Capacity
BoundedAssigned == Cardinality(active) <= Capacity
CompleteReturn == returned => active = {} /\ waiting = {} /\ (stopped \/ queued = {})
====
