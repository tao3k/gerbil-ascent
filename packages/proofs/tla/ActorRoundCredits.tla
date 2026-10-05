---- MODULE ActorRoundCredits ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Safety abstraction of native streaming batches, credit and drain. Finite
\* task inventory is TLC exploration, not a runtime generation restriction.
EXTENDS Naturals, FiniteSets
CONSTANTS Tasks, Capacity, EarlyReturn
VARIABLES queued, active, waiting, terminal, stopped, returned, badMerge
vars == <<queued, active, waiting, terminal, stopped, returned, badMerge>>
Init == /\ queued = Tasks /\ active = {} /\ waiting = {} /\ terminal = {}
        /\ stopped = FALSE /\ returned = FALSE /\ badMerge = FALSE
Dispatch(t) == /\ ~stopped /\ ~returned /\ t \in queued
               /\ Cardinality(active) < Capacity
               /\ queued' = queued \ {t} /\ active' = active \cup {t}
               /\ UNCHANGED <<waiting, terminal, stopped, returned, badMerge>>
Offer(t) == /\ ~returned /\ t \in active \ waiting
            /\ waiting' = waiting \cup {t}
            /\ UNCHANGED <<queued, active, terminal, stopped, returned, badMerge>>
Credit(t) == /\ t \in waiting /\ ~returned
             /\ waiting' = waiting \ {t}
             /\ badMerge' = badMerge
             /\ UNCHANGED <<queued, active, terminal, stopped, returned>>
\* Stop refuses merge and returns stop credit. The worker remains assigned
\* until its joining monitor reports terminal; an empty queue is insufficient.
Stop == /\ ~returned /\ ~stopped /\ stopped' = TRUE
        /\ UNCHANGED <<queued, active, waiting, terminal, returned, badMerge>>
Finish(t) == /\ t \in active \ waiting /\ ~returned
             /\ active' = active \ {t} /\ terminal' = terminal \cup {t}
             /\ UNCHANGED <<queued, waiting, stopped, returned, badMerge>>
Return == /\ ~returned
          /\ (EarlyReturn \/ (active = {} /\ (stopped \/ queued = {})))
          /\ returned' = TRUE
          /\ UNCHANGED <<queued, active, waiting, terminal, stopped, badMerge>>
Next == Stop \/ Return \/ (\E t \in Tasks : Dispatch(t) \/ Offer(t) \/ Credit(t) \/ Finish(t))
Spec == Init /\ [][Next]_vars
Partition == /\ queued \cup active \cup terminal = Tasks
             /\ queued \cap active = {} /\ queued \cap terminal = {}
             /\ active \cap terminal = {}
BoundedCredit == waiting \subseteq active /\ Cardinality(waiting) <= Capacity
BoundedAssigned == Cardinality(active) <= Capacity
CompleteReturn == returned => active = {} /\ waiting = {} /\ (stopped \/ queued = {})
====
