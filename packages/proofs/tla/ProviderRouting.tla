---- MODULE ProviderRouting ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Independent lazy row/parts cursors; no publication or generation model.
EXTENDS Naturals, Sequences
CONSTANT Mutation
Readers == {"rows", "parts"}
Queries == {"single", "reorder", "repeat", "conflict", "absent"}
Input == <<[id |-> 10,a |-> 7,b |-> 1], [id |-> 11,a |-> 7,b |-> 2],
           [id |-> 12,a |-> 9,b |-> 1], [id |-> 13,a |-> 7,b |-> 1]>>
Constraints(q) == CASE q = "single" -> <<<<0,7>>>>
  [] q = "reorder" -> <<<<1,1>>,<<0,7>>>>
  [] q = "repeat" -> <<<<0,7>>,<<0,7>>>>
  [] q = "conflict" -> <<<<0,7>>,<<0,9>>>>
  [] OTHER -> <<<<0,6>>>>
Coordinate(row,c) == IF c = 0 THEN row.a ELSE row.b
Matches(row,keys) == \A i \in 1..Len(keys) : Coordinate(row,keys[i][1]) = keys[i][2]
RECURSIVE Filter(_,_)
Filter(xs,keys) == IF Len(xs) = 0 THEN <<>> ELSE
  (IF Matches(Head(xs),keys) THEN <<Head(xs)>> ELSE <<>>) \o Filter(Tail(xs),keys)
Reverse(xs) == [i \in 1..Len(xs) |-> xs[Len(xs)-i+1]]
VARIABLES phase, query, work, emitted
vars == <<phase,query,work,emitted>>
Init == /\ phase = [r \in Readers |-> "new"] /\ query = [r \in Readers |-> "single"]
  /\ work = [r \in Readers |-> <<>>] /\ emitted = work
Build(r,q,k) == /\ phase[r] = "new" /\ k \in 1..Len(Constraints(q))
  /\ LET candidates == Filter(Input,<<Constraints(q)[k]>>) IN
    work' = [work EXCEPT ![r] = CASE Mutation = "drop" /\ Len(candidates)>0 -> Tail(candidates)
      [] Mutation = "order" -> Reverse(candidates) [] OTHER -> candidates]
  /\ phase' = [phase EXCEPT ![r] = "walk"] /\ query' = [query EXCEPT ![r] = q]
  /\ UNCHANGED emitted
Read(r) == /\ phase[r] = "walk" /\ Len(work[r]) > 0
  /\ LET row == Head(work[r])
         keys == IF Mutation = "prefix" THEN <<Head(Constraints(query[r]))>> ELSE Constraints(query[r])
         returned == IF Mutation = "representative" THEN [row EXCEPT !.id = 99] ELSE row IN
    emitted' = [emitted EXCEPT ![r] = IF Matches(row,keys) THEN Append(@,returned) ELSE @]
  /\ work' = [work EXCEPT ![r] = Tail(@)] /\ UNCHANGED <<phase,query>>
Finish(r) == /\ phase[r] = "walk" /\ work[r] = <<>>
  /\ phase' = [phase EXCEPT ![r] = "complete"] /\ UNCHANGED <<query,work,emitted>>
Cancel(r) == /\ phase[r] = "walk" /\ phase' = [phase EXCEPT ![r] = "canceled"]
  /\ UNCHANGED <<query,work,emitted>>
Next == (\E r \in Readers,q \in Queries,k \in 1..2 : Build(r,q,k))
  \/ (\E r \in Readers : Read(r) \/ Finish(r) \/ Cancel(r))
Spec == Init /\ [][Next]_vars
CompleteExact == \A r \in Readers : phase[r] = "complete" => emitted[r] = Filter(Input,Constraints(query[r]))
====
