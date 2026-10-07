---- MODULE ProviderReplay ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Publication of grouped UF rows and a newest-first presentation journal.
EXTENDS Naturals, FiniteSets, Sequences
CONSTANTS Nodes, Scopes, Mutation
VARIABLES inputs, total, journal, ordered, phase, pending, event,
          held, heldJournal, heldTotal, heldOrder, refused, saved
vars == <<inputs,total,journal,ordered,phase,pending,event,
          held,heldJournal,heldTotal,heldOrder,refused,saved>>
Rows == Scopes \X Nodes \X Nodes
\* The finite edge population bounds exploration, never semantic generation.
Edges == {e \in Rows : e[2] # e[3]}
Reverse(s) == [i \in 1..Len(s) |-> s[Len(s)-i+1]]
Range(s) == {s[i] : i \in 1..Len(s)}
Reach(rows,g,x,y) == x = y \/ <<g,x,y>> \in rows
Step(rows,e) == rows \cup {<<e[1],e[2],e[2]>>,<<e[1],e[3],e[3]>>}
               \cup {p \in Rows : p[1] = e[1] /\
                    Reach(rows,e[1],p[2],e[2]) /\ Reach(rows,e[1],e[3],p[3])}
\* Deterministic enumeration is abstracted here. Actual UF order is checked by Scheme.
Code(p) == 4*p[1] + 2*p[2] + p[3]
RECURSIVE Enumerate(_), Close(_), Replay(_)
Enumerate(rows) == IF rows = {} THEN <<>> ELSE
  LET first == CHOOSE p \in rows : \A q \in rows : Code(p) <= Code(q)
  IN <<first>> \o Enumerate(rows \ {first})
Close(rows) == LET next == rows \cup {p \in Rows : \E n \in Nodes :
  <<p[1],p[2],n>> \in rows /\ <<p[1],n,p[3]>> \in rows}
  IN IF rows = next THEN rows ELSE Close(next)
Expected(edges) == Close(edges \cup {p \in Rows : p[2] = p[3] /\
  \E e \in edges : e[1] = p[1] /\ p[2] \in {e[2],e[3]}})
Replay(events) == IF events = <<>> THEN [rows |-> {}, output |-> <<>>] ELSE
  LET prior == Replay(Tail(events))
      e == Head(events)
      rows == Step(prior.rows,e.row)
      fresh == Enumerate(rows \ prior.rows)
  IN [rows |-> rows, output |-> prior.output \o
       (IF e.kind = "derived" THEN Reverse(fresh) ELSE fresh)]
Init == /\ inputs = {} /\ total = {} /\ journal = <<>> /\ ordered = <<>>
        /\ phase = "idle" /\ pending = {} /\ event = [row |-> <<0,0,1>>,kind |-> "source"]
        /\ held = FALSE /\ heldJournal = <<>> /\ heldTotal = {} /\ heldOrder = <<>>
        /\ refused = FALSE /\ saved = <<inputs,total,journal,ordered>>
Stage(e,kind) == /\ phase = "idle" /\ e \notin inputs
  /\ event' = [row |-> e,kind |-> kind]
  /\ pending' = Step(total,IF Mutation = "scope" THEN <<0,e[2],e[3]>> ELSE e)
  /\ phase' = "pending"
  /\ journal' = (IF Mutation = "early" THEN <<[row |-> e,kind |-> kind]>> \o journal ELSE journal)
  /\ refused' = FALSE
  /\ UNCHANGED <<inputs,total,ordered,held,heldJournal,heldTotal,heldOrder,saved>>
Commit == /\ phase = "pending"
  /\ inputs' = inputs \cup {event.row} /\ total' = pending
  /\ ordered' = ordered \o (IF event.kind = "derived" THEN
                             Reverse(Enumerate(pending \ total)) ELSE Enumerate(pending \ total))
  /\ journal' = (IF Mutation = "drop" THEN journal ELSE
       <<[row |-> event.row,kind |-> IF Mutation = "kind" THEN "source" ELSE event.kind]>> \o journal)
  /\ phase' = "idle"
  /\ UNCHANGED <<pending,event,held,heldJournal,heldTotal,heldOrder,refused,saved>>
Capture == /\ phase = "idle" /\ ~held /\ held' = TRUE
  /\ heldJournal' = journal /\ heldTotal' = total /\ heldOrder' = ordered
  /\ UNCHANGED <<inputs,total,journal,ordered,phase,pending,event,refused,saved>>
Reject(e) == /\ phase = "idle" /\ e \notin inputs /\ Step(total,e) # total
  /\ refused' = TRUE /\ saved' = <<inputs,total,journal,ordered>>
  /\ journal' = (IF Mutation = "reject" THEN
       <<[row |-> e,kind |-> "source"]>> \o journal ELSE journal)
  /\ UNCHANGED <<inputs,total,ordered,phase,pending,event,held,heldJournal,heldTotal,heldOrder>>
Next == Commit \/ Capture \/ (\E e \in Edges : Reject(e) \/
           (\E kind \in {"source","derived"} : Stage(e,kind)))
Spec == Init /\ [][Next]_vars
PublishedExact == total = Expected(inputs)
JournalExact == Replay(journal).rows = total
OrderExact == Replay(journal).output = ordered /\ Range(ordered) = total /\ Len(ordered) = Cardinality(total)
HeldExact == held => LET cut == IF Mutation = "cut" THEN journal ELSE heldJournal
                    IN Replay(cut).rows = heldTotal /\ Replay(cut).output = heldOrder
RefusalAtomic == refused => <<inputs,total,journal,ordered>> = saved
====
