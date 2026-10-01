---- MODULE PositiveNonmembershipSession ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

\* Local ASCENT receipt lifecycle only. Source authority and real-world
\* completeness belong to the caller/POO Temporal model.
EXTENDS Naturals, Integers, TLC

CONSTANT MaxGeneration

Cuts == {<<a, b>> : a \in 0..1, b \in 0..1}
NoCut == <<-1, -1>>
NoGeneration == -1

VARIABLES generation, sourceCut, phase, workingGeneration, workingCut,
          certificateGeneration, certificateCut, certificateStatus,
          usedGeneration, usedCut, used

vars == <<generation, sourceCut, phase, workingGeneration, workingCut,
          certificateGeneration, certificateCut, certificateStatus,
          usedGeneration, usedCut, used>>

Init ==
  /\ generation = 0
  /\ sourceCut = <<0, 0>>
  /\ phase = "idle"
  /\ workingGeneration = NoGeneration
  /\ workingCut = NoCut
  /\ certificateGeneration = NoGeneration
  /\ certificateCut = NoCut
  /\ certificateStatus = "none"
  /\ usedGeneration = NoGeneration
  /\ usedCut = NoCut
  /\ used = FALSE

\* Replacing multiple source relations is one visible generation change.
\* A computation that began on an older cut may finish, but cannot publish.
SwapSources ==
  /\ generation < MaxGeneration
  /\ \E nextCut \in Cuts :
       /\ nextCut # sourceCut
       /\ sourceCut' = nextCut
  /\ generation' = generation + 1
  /\ certificateGeneration' = NoGeneration
  /\ certificateCut' = NoCut
  /\ certificateStatus' = "none"
  /\ used' = FALSE
  /\ usedGeneration' = NoGeneration
  /\ usedCut' = NoCut
  /\ UNCHANGED <<phase, workingGeneration, workingCut>>

StartProof ==
  /\ phase = "idle"
  /\ phase' = "working"
  /\ workingGeneration' = generation
  /\ workingCut' = sourceCut
  /\ certificateGeneration' = NoGeneration
  /\ certificateCut' = NoCut
  /\ certificateStatus' = "none"
  /\ UNCHANGED <<generation, sourceCut,
                 usedGeneration, usedCut, used>>

FinishComplete ==
  /\ phase = "working"
  /\ phase' = "idle"
  /\ IF workingGeneration = generation /\ workingCut = sourceCut
     THEN /\ certificateGeneration' = generation
          /\ certificateCut' = sourceCut
          /\ certificateStatus' = "valid"
     ELSE /\ certificateGeneration' = NoGeneration
          /\ certificateCut' = NoCut
          /\ certificateStatus' = "none"
  /\ workingGeneration' = NoGeneration
  /\ workingCut' = NoCut
  /\ UNCHANGED <<generation, sourceCut,
                 usedGeneration, usedCut, used>>

FinishBounded ==
  /\ phase = "working"
  /\ phase' = "idle"
  /\ workingGeneration' = NoGeneration
  /\ workingCut' = NoCut
  /\ certificateGeneration' = NoGeneration
  /\ certificateCut' = NoCut
  /\ certificateStatus' = "bounded"
  /\ UNCHANGED <<generation, sourceCut,
                 usedGeneration, usedCut, used>>

UseCertificate ==
  /\ certificateStatus = "valid"
  /\ certificateGeneration = generation
  /\ certificateCut = sourceCut
  /\ used' = TRUE
  /\ usedGeneration' = certificateGeneration
  /\ usedCut' = certificateCut
  /\ UNCHANGED <<generation, sourceCut, phase,
                 workingGeneration, workingCut,
                 certificateGeneration, certificateCut,
                 certificateStatus>>

Next ==
  SwapSources \/ StartProof \/ FinishComplete \/ FinishBounded
  \/ UseCertificate

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ generation \in 0..MaxGeneration
  /\ sourceCut \in Cuts
  /\ phase \in {"idle", "working"}
  /\ workingGeneration \in {NoGeneration} \cup 0..MaxGeneration
  /\ workingCut \in {NoCut} \cup Cuts
  /\ certificateGeneration \in {NoGeneration} \cup 0..MaxGeneration
  /\ certificateCut \in {NoCut} \cup Cuts
  /\ certificateStatus \in {"none", "bounded", "valid"}
  /\ usedGeneration \in {NoGeneration} \cup 0..MaxGeneration
  /\ usedCut \in {NoCut} \cup Cuts
  /\ used \in BOOLEAN

NoStalePublished ==
  certificateStatus = "valid" =>
    certificateGeneration = generation /\ certificateCut = sourceCut

NoStaleUse ==
  used => usedGeneration = generation /\ usedCut = sourceCut

====
