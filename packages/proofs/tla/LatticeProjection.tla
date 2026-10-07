---- MODULE LatticeProjection ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* One refinement/publication transaction; finite populations, no generation cap.
EXTENDS Naturals, FiniteSets
CONSTANT Mutation
Keys == {0,1}
Values == {0,1,2}
Events == Keys \X Values
Seed == [k \in Keys |-> 2]
RowsOf(store) == {<<k,store[k]>> : k \in Keys}
\* Independent truth from all admitted inputs, without replaying update order.
Expected(events) == [k \in Keys |->
  CHOOSE v \in Values :
    /\ (v = 2 \/ <<k,v>> \in events)
    /\ \A w \in Values : <<k,w>> \in events => v <= w]
VARIABLES cut, applied, current, rows, held, phase
vars == <<cut,applied,current,rows,held,phase>>
Init == /\ cut = {} /\ applied = {} /\ current = Seed
        /\ rows = RowsOf(Seed) /\ held = rows /\ phase = "initial"
Begin == /\ phase = "initial" /\ cut' \in SUBSET Events
         /\ phase' = "collecting"
         /\ UNCHANGED <<applied,current,rows,held>>
Inject(e) == /\ phase = "collecting" /\ e \in cut \ applied
  /\ applied' = applied \cup {e}
  /\ current' = (IF Mutation = "false" /\ e[1] = 0 THEN current ELSE
       [current EXCEPT ![e[1]] =
          IF Mutation = "overwrite" THEN e[2]
          ELSE IF Mutation = "prior" THEN IF Seed[e[1]] <= e[2] THEN Seed[e[1]] ELSE e[2]
          ELSE IF @ <= e[2] THEN @ ELSE e[2]])
  /\ UNCHANGED <<cut,rows,held,phase>>
Settle == /\ phase = "collecting"
          /\ (applied = cut \/ Mutation = "early") /\ phase' = "settled"
          /\ UNCHANGED <<cut,applied,current,rows,held>>
Publish == /\ phase = "settled" /\ phase' = "finished"
  /\ rows' = (IF Mutation = "retain" THEN rows \cup RowsOf(current)
              ELSE IF Mutation = "stale" THEN rows ELSE RowsOf(current))
  /\ held' = (IF Mutation = "borrow" THEN RowsOf(current) ELSE held)
  /\ UNCHANGED <<cut,applied,current>>
Next == Begin \/ (\E e \in Events : Inject(e)) \/ Settle \/ Publish
Spec == Init /\ [][Next]_vars
MapExact == current = Expected(applied)
SnapshotExact == phase = "finished" => rows = RowsOf(Expected(cut))
PrivateStable == phase \in {"initial","collecting","settled"} => rows = RowsOf(Seed)
HeldStable == held = RowsOf(Seed)
====
