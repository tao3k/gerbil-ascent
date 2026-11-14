// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module PositiveNonmembershipSession {
  const GenerationCutoff: int
  type Cut = (int,int)
  pure val Cuts = tuples(Set(0,1),Set(0,1))
  pure val NoCut = (-1,-1)
  type State = {generation: int, sourceCut: Cut, phase: str, workingGeneration: int, workingCut: Cut,
    certificateGeneration: int, certificateCut: Cut, certificateStatus: str, usedGeneration: int, usedCut: Cut, used: bool}
  var q: State
  action init = q' = {generation: 0, sourceCut: (0,0), phase: "idle", workingGeneration: -1, workingCut: NoCut,
    certificateGeneration: -1, certificateCut: NoCut, certificateStatus: "none", usedGeneration: -1, usedCut: NoCut, used: false}
  action SwapSources = {nondet cut = Cuts.oneOf(); all {cut != q.sourceCut, q' = {...q, sourceCut: cut, generation: q.generation+1,
    certificateGeneration: -1, certificateCut: NoCut, certificateStatus: "none", used: false, usedGeneration: -1, usedCut: NoCut}}}
  action StartProof = all {q.phase == "idle", q' = {...q, phase: "working", workingGeneration: q.generation, workingCut: q.sourceCut,
    certificateGeneration: -1, certificateCut: NoCut, certificateStatus: "none"}}
  action FinishComplete = all {q.phase == "working", q' = {...q, phase: "idle", workingGeneration: -1, workingCut: NoCut,
    certificateGeneration: if (q.workingGeneration == q.generation and q.workingCut == q.sourceCut) q.generation else -1,
    certificateCut: if (q.workingGeneration == q.generation and q.workingCut == q.sourceCut) q.sourceCut else NoCut,
    certificateStatus: if (q.workingGeneration == q.generation and q.workingCut == q.sourceCut) "valid" else "none"}}
  action FinishBounded = all {q.phase == "working", q' = {...q, phase: "idle", workingGeneration: -1, workingCut: NoCut,
    certificateGeneration: -1, certificateCut: NoCut, certificateStatus: "bounded"}}
  action UseCertificate = all {q.certificateStatus == "valid", q.certificateGeneration == q.generation, q.certificateCut == q.sourceCut,
    q' = {...q, used: true, usedGeneration: q.certificateGeneration, usedCut: q.certificateCut}}
  action step = any {SwapSources, StartProof, FinishComplete, FinishBounded, UseCertificate}
  val TypeOK = all {q.generation >= 0, Cuts.contains(q.sourceCut), Set("idle","working").contains(q.phase),
    q.workingGeneration >= -1, Cuts.union(Set(NoCut)).contains(q.workingCut), q.certificateGeneration >= -1,
    Cuts.union(Set(NoCut)).contains(q.certificateCut), Set("none","bounded","valid").contains(q.certificateStatus),
    q.usedGeneration >= -1, Cuts.union(Set(NoCut)).contains(q.usedCut), Set(true,false).contains(q.used)}
  val ExplorationBound = q.generation <= GenerationCutoff
  val NoStalePublished = q.certificateStatus == "valid" implies (q.certificateGeneration == q.generation and q.certificateCut == q.sourceCut)
  val NoStaleUse = q.used implies (q.usedGeneration == q.generation and q.usedCut == q.sourceCut)

}
