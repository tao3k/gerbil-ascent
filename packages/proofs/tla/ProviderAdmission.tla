---- MODULE ProviderAdmission ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Whole custom index packet admission before callbacks; rows are abstract IDs.
EXTENDS Naturals, FiniteSets, Sequences
CONSTANTS Rows, Keys, Total, Delta, KeyOf, Mutation
VARIABLES lane, wanted, packet, approved, result, phase, cacheLive,
          callbacks, mutated, retried
vars == <<lane,wanted,packet,approved,result,phase,cacheLive,callbacks,mutated,retried>>
TotalRows == <<0,0,1,2>>
DeltaRows == <<0>>
RowKey == [r \in Rows |-> IF r < 2 THEN 0 ELSE 1]
Zero == [r \in Rows |-> 0]
Occurrences(s) == [r \in Rows |-> Cardinality({i \in 1..Len(s) : s[i] = r})]
Source(which) == Occurrences(IF which = "all" THEN Total ELSE Delta)
RECURSIVE Mass(_,_)
Mass(p,rs) == IF rs = {} THEN 0 ELSE
  LET r == CHOOSE x \in rs : TRUE IN p[r] + Mass(p,rs \ {r})
Bucket(k) == {r \in Rows : KeyOf[r] = k}
Cap(p,w) == \A r \in Rows : p[r] <= w[r]
Matching(p,w,k) == Mass(p,Bucket(k)) = Mass(w,Bucket(k))
SetMatching(p,w,k) == \A r \in Bucket(k) : (p[r] > 0) = (w[r] > 0)
Admissible(p,w,k) == Cap(p,w) /\ Matching(p,w,k)
Selected(p,k) == [r \in Rows |-> IF KeyOf[r] = k THEN p[r] ELSE 0]
\* Packet counts explore excess and foreign enumeration, including duplicates.
\* This finite packet population is not a semantic runtime or generation cap.
Packets == [Rows -> 0..(Len(Total)+1)]
Init == /\ lane = "all" /\ wanted = CHOOSE k \in Keys : TRUE
        /\ packet = Zero /\ approved = Zero /\ result = Zero
        /\ phase = "idle" /\ cacheLive = TRUE /\ callbacks = 0
        /\ mutated = FALSE /\ retried = FALSE
Submit(which,k,p) == /\ phase = "idle" /\ lane' = which /\ wanted' = k
  /\ packet' = p /\ phase' = "returned"
  /\ UNCHANGED <<approved,result,cacheLive,callbacks,mutated,retried>>
Check == LET witness == Source(IF Mutation = "allwitness" THEN "all" ELSE lane)
             ok == IF Mutation = "nocap" THEN Matching(packet,witness,wanted)
                   ELSE IF Mutation = "set" THEN Cap(packet,witness) /\ SetMatching(packet,witness,wanted)
                   ELSE Admissible(packet,witness,wanted)
         IN /\ phase = "returned"
            /\ phase' = IF ok THEN "admitted" ELSE "failed"
            /\ approved' = IF ok THEN packet ELSE Zero
            /\ cacheLive' = (IF ok THEN cacheLive ELSE Mutation = "retain")
            /\ callbacks' = IF Mutation = "early" /\ ~ok THEN 1 ELSE 0
            /\ UNCHANGED <<lane,wanted,packet,result,mutated,retried>>
MutateBuffer == /\ phase = "admitted" /\ ~mutated
  /\ packet' = Zero /\ mutated' = TRUE
  /\ UNCHANGED <<lane,wanted,approved,result,phase,cacheLive,callbacks,retried>>
Consume == /\ phase = "admitted" /\ phase' = "done" /\ callbacks' = 1
  /\ result' = Selected(IF Mutation = "borrow" THEN packet ELSE approved,wanted)
  /\ UNCHANGED <<lane,wanted,packet,approved,cacheLive,mutated,retried>>
Retry == /\ phase = "failed" /\ ~retried /\ phase' = "idle"
  /\ cacheLive' = TRUE /\ callbacks' = 0 /\ retried' = TRUE
  /\ packet' = Zero /\ approved' = Zero /\ result' = Zero /\ mutated' = FALSE
  /\ UNCHANGED <<lane,wanted>>
Next == Check \/ MutateBuffer \/ Consume \/ Retry \/
  (/\ phase = "idle"
   /\ \E which \in {"all","delta"}, k \in Keys, p \in Packets : Submit(which,k,p))
Spec == Init /\ [][Next]_vars
CountCaps == phase \in {"admitted","done"} => Cap(approved,Source(lane))
MatchingExact == phase \in {"admitted","done"} =>
  \A r \in Bucket(wanted) : approved[r] = Source(lane)[r]
OutputExact == phase = "done" => result = Selected(Source(lane),wanted)
DetachedPacket == phase = "done" => result = Selected(approved,wanted)
NoEarlyCallbacks == phase \in {"idle","returned","failed"} => callbacks = 0
FailedCacheRevoked == phase = "failed" => ~cacheLive
====
