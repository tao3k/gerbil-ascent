---- MODULE LatticeProjection ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* One refinement/publication transaction; finite populations, no generation cap.
EXTENDS Naturals, FiniteSets
CONSTANTS Mutation, Remaining
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
VARIABLES cut, applied, current, dirty, rows, held, phase, refusedCost
\* Remaining is an application resource parameter, not a generation limit.
\* An ineffective event or improvement to an already staged key has zero cost.
NextDirty(e) == IF e[2] < current[e[1]] THEN dirty \cup {e[1]} ELSE dirty
PendingCost(e) == Cardinality(NextDirty(e))
AdmissionCost(e) == IF Mutation = "budget-events" THEN Cardinality(applied) + 1 ELSE PendingCost(e)
Apply(store,e) == [store EXCEPT ![e[1]] = IF @ <= e[2] THEN @ ELSE e[2]]
vars == <<cut,applied,current,dirty,rows,held,phase,refusedCost>>
Init == /\ cut = {} /\ applied = {} /\ current = Seed /\ dirty = {}
        /\ rows = RowsOf(Seed) /\ held = rows /\ phase = "initial" /\ refusedCost = 0
Begin == /\ phase = "initial" /\ cut' \in SUBSET Events
         /\ phase' = "collecting"
         /\ UNCHANGED <<applied,current,dirty,rows,held,refusedCost>>
Inject(e) == /\ phase = "collecting" /\ e \in cut \ applied
  /\ (AdmissionCost(e) <= Remaining \/ Mutation = "budget-skip")
  /\ applied' = applied \cup {e}
  /\ current' = (IF Mutation = "false" /\ e[1] = 0 THEN current ELSE
       [current EXCEPT ![e[1]] =
          IF Mutation = "overwrite" THEN e[2]
          ELSE IF Mutation = "prior" THEN IF Seed[e[1]] <= e[2] THEN Seed[e[1]] ELSE e[2]
          ELSE IF @ <= e[2] THEN @ ELSE e[2]])
  /\ dirty' = (IF e[2] >= current[e[1]] THEN dirty
       ELSE IF Mutation = "lost-key" /\ e[1] = 0 THEN dirty
       ELSE IF Mutation = "repeat-key" /\ e[1] \in dirty THEN dirty \ {e[1]}
       ELSE dirty \cup {e[1]})
  /\ UNCHANGED <<cut,rows,held,phase,refusedCost>>
\* Failed admission may leave private buffers changed. Only their publication
\* is prohibited; the model does not assume physical rollback of user callbacks.
Refuse(e) == /\ phase = "collecting" /\ e \in cut \ applied
  /\ AdmissionCost(e) > Remaining /\ Mutation # "budget-skip"
  /\ phase' = "refused" /\ refusedCost' = PendingCost(e)
  /\ applied' = applied \cup {e} /\ current' = Apply(current,e)
  /\ dirty' = NextDirty(e)
  /\ rows' = (IF Mutation = "refusal-publish" THEN RowsOf(Apply(current,e)) ELSE rows)
  /\ UNCHANGED <<cut,held>>
Settle == /\ phase = "collecting"
          /\ (applied = cut \/ Mutation = "early") /\ phase' = "settled"
          /\ UNCHANGED <<cut,applied,current,dirty,rows,held,refusedCost>>
Publish == /\ phase = "settled" /\ phase' = "finished"
  /\ rows' = (IF Mutation = "retain" THEN rows \cup RowsOf(current)
              ELSE IF Mutation = "stale" THEN rows
              ELSE {row \in rows : row[1] \notin dirty} \cup
                   {<<k,current[k]>> : k \in dirty})
  /\ held' = (IF Mutation = "borrow" THEN RowsOf(current) ELSE held)
  /\ UNCHANGED <<cut,applied,current,dirty,refusedCost>>
Next == Begin \/ (\E e \in Events : Inject(e) \/ Refuse(e)) \/ Settle \/ Publish
Spec == Init /\ [][Next]_vars
MapExact == current = Expected(applied)
SnapshotExact == phase = "finished" => rows = RowsOf(Expected(cut))
KeyCoverage == dirty = {k \in Keys : current[k] # Seed[k]}
BudgetBound == phase # "refused" => Cardinality(dirty) <= Remaining
RefusalSound == phase = "refused" => refusedCost > Remaining
RefusalStable == phase = "refused" => rows = RowsOf(Seed)
PrivateStable == phase \in {"initial","collecting","settled"} => rows = RowsOf(Seed)
HeldStable == held = RowsOf(Seed)
====
