---- MODULE SessionTransaction ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\* Publication protocol over one symbolic row of a branch-scoped rule.
\* This is not a Datalog evaluator or a Gerbil refinement proof.
EXTENDS Naturals, Integers, TLC
CONSTANTS ExplorationDepth, Mutation
\* Direct, via, and lower-stratum exclusion membership for one row.
Cuts == {<<d, v, b>> : d \in 0..1, v \in 0..1, b \in 0..1}
\* Negation belongs to the via branch before union with direct.
ResultOf(cut) == IF cut[1] = 1 \/ (cut[2] = 1 /\ cut[3] = 0)
                 THEN {1} ELSE {}
\* Wrong lowering: move the exclusion after the union.
GlobalResultOf(cut) == IF (cut[1] = 1 \/ cut[2] = 1) /\ cut[3] = 0
                       THEN {1} ELSE {}
VARIABLES generation, source, result, phase, base, pending, candidate, complete
vars == <<generation, source, result, phase, base, pending, candidate, complete>>
Init ==
  /\ generation = 0
  /\ source = <<0, 0, 0>>
  /\ result = ResultOf(source)
  /\ phase = "idle"
  /\ base = -1
  /\ pending = source
  /\ candidate = {}
  /\ complete = FALSE
Begin ==
  /\ phase = "idle"
  /\ \E cut \in Cuts : pending' = cut
  /\ base' = generation
  /\ phase' = "solving"
  /\ candidate' = {}
  /\ complete' = FALSE
  /\ UNCHANGED <<generation, source, result>>
Solve ==
  /\ phase = "solving"
  /\ candidate' = IF Mutation = "global" THEN GlobalResultOf(pending)
                  ELSE ResultOf(pending)
  /\ complete' = TRUE
  /\ phase' = "ready"
  /\ UNCHANGED <<generation, source, result, base, pending>>
\* Another publication may race a prospective solve. Old work cannot commit.
ExternalCommit ==
  /\ \E cut \in Cuts : /\ source' = cut /\ result' = ResultOf(cut)
  /\ generation' = generation + 1
  /\ UNCHANGED <<phase, base, pending, candidate, complete>>
Commit ==
  /\ phase = "ready"
  /\ complete
  /\ base = generation \/ Mutation = "stale"
  /\ generation' = generation + 1
  /\ source' = pending
  /\ result' = candidate
  /\ phase' = "idle"
  /\ UNCHANGED <<base, pending, candidate, complete>>
\* Domain/budget/unsupported failures and cancellation discard private work.
Abort ==
  /\ phase # "idle"
  /\ phase' = "idle"
  /\ complete' = FALSE
  /\ candidate' = {}
  /\ UNCHANGED <<generation, source, result, base, pending>>
EarlyPublish ==
  /\ Mutation = "early"
  /\ phase = "solving"
  /\ source' = pending
  /\ UNCHANGED <<generation, result, phase, base, pending, candidate, complete>>
Next == Begin \/ Solve \/ Commit \/ Abort \/ ExternalCommit \/ EarlyPublish
Spec == Init /\ [][Next]_vars
TypeOK ==
  /\ generation \in Nat
  /\ source \in Cuts /\ pending \in Cuts
  /\ result \subseteq {1} /\ candidate \subseteq {1}
  /\ base \in {-1} \cup Nat
  /\ phase \in {"idle", "solving", "ready"}
  /\ complete \in BOOLEAN
\* TLC-only exploration constraint. Spec does not reference this bound.
ExplorationBound == generation <= ExplorationDepth
AtomicSnapshot == result = ResultOf(source)
NoStaleCommit == [][Commit => base = generation]_vars
AbortPreservesSnapshot == [][Abort => UNCHANGED <<generation, source, result>>]_vars
====
