---- MODULE NativeSessionPublication ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
\*
\* Synchronous retained Session replacement/run abstraction. The state
\* names follow program/session.ss's pending, committed, committed-result,
\* clean? and partial? observations. The model does not extract Scheme steps,
\* cover source append, or establish a native trace refinement.
EXTENDS Naturals, Integers, TLC
CONSTANTS TLCGenerationCutoff, Mutation

\* One symbolic answer row; direct, via, blocked source membership.
Cuts == {<<d, v, b>> : d \in 0..1, v \in 0..1, b \in 0..1}
ResultOf(cut) == IF cut[1] = 1 \/ (cut[2] = 1 /\ cut[3] = 0)
                 THEN {1} ELSE {}

VARIABLES generation, committed, pending, published, phase, outcome
vars == <<generation, committed, pending, published, phase, outcome>>

Init ==
  /\ generation = 0
  /\ committed = <<0, 0, 0>>
  /\ pending = committed
  /\ published = ResultOf(committed)
  /\ phase = "clean"
  /\ outcome = "complete"

\* replace-source!: a successful single-source replacement stays pending
\* until an unrestricted or completed timed run. An append of an owned row
\* has the same public cut transition; private incremental engine steps are
\* outside this model. A wrong early publication is the first negative control.
SingleReplace ==
  /\ phase # "partial"
  /\ \E cut \in Cuts :
       /\ pending' = cut
       /\ published' = IF Mutation = "early" THEN ResultOf(cut)
                       ELSE published
  /\ phase' = "dirty"
  /\ outcome' = "provisional"
  /\ UNCHANGED <<generation, committed>>

\* replace-sources!: the prospective solve finishes before one visible
\* source/result publication. Rejection has no public state change.
BatchComplete ==
  /\ phase = "clean"
  /\ \E cut \in Cuts :
       /\ pending' = cut
       /\ committed' = cut
       /\ published' = ResultOf(cut)
  /\ generation' = generation + 1
  /\ phase' = "clean"
  /\ outcome' = "complete"

BatchReject ==
  /\ phase = "clean"
  /\ outcome' = "rejected"
  /\ UNCHANGED <<generation, committed, pending, published, phase>>

\* A successful run commits the pending cut; a bounded timed run keeps the
\* last completed source/result pair. Publishing its partial answer is the
\* second negative control. A failed run restores the committed cut.
RunComplete ==
  /\ phase \in {"dirty", "partial"}
  /\ committed' = pending
  /\ published' = ResultOf(pending)
  /\ generation' = generation + 1
  /\ phase' = "clean"
  /\ outcome' = "complete"
  /\ UNCHANGED pending

RunBounded ==
  /\ phase \in {"dirty", "partial"}
  /\ published' = IF Mutation = "bounded" THEN ResultOf(pending)
                  ELSE published
  /\ phase' = "partial"
  /\ outcome' = "bounded"
  /\ UNCHANGED <<generation, committed, pending>>

RunFailure ==
  /\ phase \in {"dirty", "partial"}
  /\ pending' = committed
  /\ phase' = "clean"
  /\ outcome' = "rejected"
  /\ UNCHANGED <<generation, committed, published>>

\* Fault injection: changing the contents of a committed source value through
\* a shared mutable alias is not a legal Session transition. It demonstrates
\* the immutable-cut premise needed by the normal publication invariant.
SourceAlias ==
  /\ Mutation = "alias"
  /\ phase = "clean"
  /\ \E cut \in Cuts :
       /\ cut # committed
       /\ committed' = cut
       /\ pending' = cut
  /\ UNCHANGED <<generation, published, phase, outcome>>

Next == SingleReplace \/ BatchComplete \/ BatchReject \/ RunComplete
        \/ RunBounded \/ RunFailure \/ SourceAlias
Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ generation \in Nat
  /\ committed \in Cuts /\ pending \in Cuts
  /\ published \subseteq {1}
  /\ phase \in {"clean", "dirty", "partial"}
  /\ outcome \in {"complete", "provisional", "bounded", "rejected"}

\* TLC-only state constraint; not a limit on the Session API.
ExplorationBound == generation <= TLCGenerationCutoff
CommittedSnapshot == published = ResultOf(committed)
CleanAligned == phase = "clean" => pending = committed
PartialBounded == phase = "partial" => outcome = "bounded"
NoPrematurePublication ==
  [][(SingleReplace \/ RunBounded \/ BatchReject \/ RunFailure) =>
     UNCHANGED <<generation, committed, published>>]_vars
====
