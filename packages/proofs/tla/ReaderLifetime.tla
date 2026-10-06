---- MODULE ReaderLifetime ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Finite reader-lifetime abstraction. "current" is a compatibility bit,
\* not a bounded generation: any publication invalidates an active reader
\* irreversibly until release, even if the row set later returns (ABA).
EXTENDS Naturals, FiniteSets
CONSTANTS Rows, Budget, Mutation
VARIABLES committed, reading, canceled, alive, current, captured, accepted
vars == <<committed, reading, canceled, alive, current, captured, accepted>>
Init == /\ committed = {} /\ reading = FALSE /\ canceled = FALSE
        /\ alive = FALSE /\ current = TRUE /\ captured = {} /\ accepted = FALSE
Publish == /\ \E next \in SUBSET Rows :
                  /\ Cardinality(next) <= Budget /\ committed' = next
           /\ current' = IF reading THEN FALSE ELSE current
           /\ accepted' = FALSE
           /\ UNCHANGED <<reading, canceled, alive, captured>>
Borrow == /\ ~reading /\ reading' = TRUE /\ canceled' = FALSE
          /\ alive' = TRUE /\ current' = TRUE /\ captured' = committed
          /\ accepted' = FALSE /\ UNCHANGED committed
Cancel == /\ reading /\ ~canceled /\ canceled' = TRUE
          /\ UNCHANGED <<committed, reading, alive, current, captured, accepted>>
Drain == /\ reading /\ canceled /\ reading' = FALSE /\ alive' = FALSE
         /\ UNCHANGED <<committed, canceled, current, captured, accepted>>
Reply == /\ reading /\ ~canceled /\ current
         /\ reading' = FALSE /\ alive' = FALSE /\ accepted' = TRUE
         /\ UNCHANGED <<committed, canceled, current, captured>>
Discard == /\ reading /\ ~canceled /\ ~current /\ Mutation # "stuck"
           /\ reading' = FALSE /\ alive' = FALSE
           /\ UNCHANGED <<committed, canceled, current, captured, accepted>>
Finish == Drain \/ Reply \/ Discard
Next == Publish \/ Borrow \/ Cancel \/ Finish
Spec == Init /\ [][Next]_vars /\
        (IF Mutation = "unfair" THEN TRUE ELSE WF_vars(Finish))
ReaderCompletion == reading ~> ~reading
ReaderAlive == reading => alive
AcceptedCurrent == accepted => current /\ captured = committed
====
