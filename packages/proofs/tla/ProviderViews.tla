---- MODULE ProviderViews ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Frozen view lifetime and staged publication, not relation closure algebra.
EXTENDS Naturals, FiniteSets, TLC
CONSTANTS Rows, Budget, Mutation, ExplorationBound
VARIABLES generation, committed, published, candidate, phase,
          reading, canceled, alive, captured, observed,
          replyAccepted, replyRevision, replyRows
vars == <<generation, committed, published, candidate, phase,
          reading, canceled, alive, captured, observed,
          replyAccepted, replyRevision, replyRows>>
\* One symbolic compressed descriptor can denote several logical rows.
DescriptorCount(cut) == IF cut = {} THEN 0 ELSE 1
Init == /\ generation = 0 /\ committed = {} /\ published = <<0, {}>>
        /\ candidate = {} /\ phase = "idle"
        /\ reading = FALSE /\ canceled = FALSE /\ alive = FALSE
        /\ captured = <<0, {}>> /\ observed = <<0, {}>>
        /\ replyAccepted = FALSE /\ replyRevision = 0 /\ replyRows = {}
Stage == /\ phase = "idle"
         /\ \E next \in SUBSET Rows :
              /\ next # committed
              /\ candidate' = next
              /\ phase' = "staged"
              /\ published' = IF Mutation = "early" THEN <<generation + 1, next>> ELSE published
         /\ UNCHANGED <<generation, committed, reading, canceled, alive,
                         captured, observed, replyAccepted, replyRevision, replyRows>>
Publish == /\ phase = "staged"
           /\ (IF Mutation = "budget" THEN DescriptorCount(candidate) <= Budget
               ELSE Cardinality(candidate) <= Budget)
           /\ generation' = generation + 1 /\ committed' = candidate
           /\ published' = <<generation + 1, candidate>> /\ phase' = "idle"
           /\ observed' = IF Mutation = "alias" /\ reading
                           THEN <<generation + 1, candidate>> ELSE observed
           /\ replyAccepted' = FALSE
           /\ UNCHANGED <<candidate, reading, canceled, alive, captured, replyRevision, replyRows>>
Reject == /\ phase = "staged" /\ Cardinality(candidate) > Budget
          /\ phase' = "idle"
          /\ UNCHANGED <<generation, committed, published, candidate,
                          reading, canceled, alive, captured, observed,
                          replyAccepted, replyRevision, replyRows>>
Borrow == /\ ~reading /\ ~replyAccepted
          /\ reading' = TRUE /\ canceled' = FALSE /\ alive' = TRUE
          /\ captured' = published /\ observed' = published
          /\ UNCHANGED <<generation, committed, published, candidate, phase,
                          replyAccepted, replyRevision, replyRows>>
Cancel == /\ reading /\ ~canceled /\ canceled' = TRUE
          /\ alive' = IF Mutation = "retire" THEN FALSE ELSE alive
          /\ UNCHANGED <<generation, committed, published, candidate, phase,
                          reading, captured, observed, replyAccepted, replyRevision, replyRows>>
Drain == /\ reading /\ canceled /\ reading' = FALSE /\ alive' = FALSE
         /\ UNCHANGED <<generation, committed, published, candidate, phase,
                         canceled, captured, observed, replyAccepted, replyRevision, replyRows>>
Reply == /\ reading /\ ~canceled
         /\ (captured[1] = generation \/ Mutation = "stale")
         /\ replyAccepted' = TRUE /\ replyRevision' = captured[1] /\ replyRows' = observed[2]
         /\ reading' = FALSE /\ alive' = FALSE
         /\ UNCHANGED <<generation, committed, published, candidate, phase,
                         canceled, captured, observed>>
\* A stale consumer must release its credit without publishing its old rows.
Discard == /\ reading /\ ~canceled /\ captured[1] # generation
           /\ Mutation # "stuck"
           /\ reading' = FALSE /\ alive' = FALSE
           /\ UNCHANGED <<generation, committed, published, candidate, phase,
                           canceled, captured, observed,
                           replyAccepted, replyRevision, replyRows>>
Finish == Drain \/ Reply \/ Discard
Next == Stage \/ Publish \/ Reject \/ Borrow \/ Cancel \/ Finish
Spec == Init /\ [][Next]_vars
\* No generation maximum in Init/Next/Spec. TLC's finite constraint is separate.
Explore == generation <= ExplorationBound
AtomicPublication == published = <<generation, committed>>
FrozenRead == reading => observed = captured
ReaderAlive == reading => alive
CurrentReply == replyAccepted => replyRevision = generation /\ replyRows = committed
LogicalBudget == Cardinality(committed) <= Budget
====
