---- MODULE ReaderLifetime ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite multi-reader compatibility abstraction, not a bounded generation.
\* Publication invalidates each active reader until release even for equal rows.
EXTENDS Naturals, FiniteSets
CONSTANTS Rows, Readers, Budget, Mutation
VARIABLES committed, reading, canceled, alive, current, valid, captured, accepted, credits
vars == <<committed, reading, canceled, alive, current, valid, captured, accepted, credits>>
Init == /\ committed = {} /\ reading = {} /\ canceled = {} /\ alive = FALSE
        /\ current = [r \in Readers |-> TRUE] /\ valid = current
        /\ captured = [r \in Readers |-> {}] /\ accepted = {} /\ credits = 0
Publish == /\ \E next \in SUBSET Rows :
                  /\ Cardinality(next) <= Budget /\ committed' = next
                  /\ current' = [r \in Readers |-> IF r \in reading THEN
                        IF Mutation = "aba" THEN captured[r] = next ELSE FALSE
                        ELSE current[r]]
           /\ valid' = [r \in Readers |-> IF r \in reading THEN FALSE ELSE valid[r]]
           /\ accepted' = {}
           /\ UNCHANGED <<reading, canceled, alive, captured, credits>>
Borrow(r) == /\ r \notin reading /\ reading' = reading \cup {r}
             /\ canceled' = canceled \ {r} /\ alive' = TRUE
             /\ current' = [current EXCEPT ![r] = TRUE]
             /\ valid' = [valid EXCEPT ![r] = TRUE]
             /\ captured' = [captured EXCEPT ![r] = committed]
             /\ accepted' = accepted \ {r} /\ credits' = credits + 1
             /\ UNCHANGED committed
Cancel(r) == /\ r \in reading \ canceled /\ canceled' = canceled \cup {r}
             /\ UNCHANGED <<committed, reading, alive, current, valid, captured, accepted, credits>>
Release(r) == /\ reading' = reading \ {r}
              /\ alive' = IF Mutation = "retire" THEN FALSE ELSE reading \ {r} # {}
              /\ credits' = IF Mutation = "credit" THEN credits ELSE credits - 1
Drain(r) == /\ r \in reading \cap canceled /\ Release(r)
            /\ UNCHANGED <<committed, canceled, current, valid, captured, accepted>>
Reply(r) == /\ r \in reading \ canceled /\ current[r] /\ Release(r)
            /\ accepted' = accepted \cup {r}
            /\ UNCHANGED <<committed, canceled, current, valid, captured>>
Discard(r) == /\ r \in reading \ canceled /\ ~current[r] /\ Mutation # "stuck"
              /\ Release(r)
              /\ UNCHANGED <<committed, canceled, current, valid, captured, accepted>>
Finish(r) == Drain(r) \/ Reply(r) \/ Discard(r)
Next == Publish \/ (\E r \in Readers : Borrow(r) \/ Cancel(r) \/ Finish(r))
Spec == Init /\ [][Next]_vars /\
        (IF Mutation = "unfair" THEN TRUE
         ELSE IF Mutation = "global" THEN WF_vars(\E r \in Readers : Finish(r))
         ELSE \A r \in Readers : WF_vars(Finish(r)))
ReaderCompletion == \A r \in Readers : (r \in reading) ~> (r \notin reading)
ReaderAlive == reading # {} => alive
CreditBalance == credits = Cardinality(reading)
AcceptedCurrent == \A r \in accepted : valid[r] /\ captured[r] = committed
====
