// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module NativeSessionPublication {
  const GenerationCutoff: int
  const Mutation: str
  type Cut = (int,int,int)
  pure val Cuts = tuples(Set(0,1),Set(0,1),Set(0,1))
  pure def ResultOf(cut: Cut): Set[int] = if (cut._1 == 1 or (cut._2 == 1 and cut._3 == 0)) Set(1) else Set()
  type State = {generation: int, committed: Cut, pending: Cut, published: Set[int], phase: str, outcome: str}
  var q: State
  action init = q' = {generation: 0, committed: (0,0,0), pending: (0,0,0), published: Set(), phase: "clean", outcome: "complete"}
  action SingleReplace = {nondet cut = Cuts.oneOf(); all {q.phase != "partial", q' = {...q, pending: cut,
    published: if (Mutation == "early") ResultOf(cut) else q.published, phase: "dirty", outcome: "provisional"}}}
  action BatchComplete = {nondet cut = Cuts.oneOf(); all {q.phase == "clean", q' = {...q, pending: cut, committed: cut,
    published: ResultOf(cut), generation: q.generation+1, phase: "clean", outcome: "complete"}}}
  action BatchReject = all {q.phase == "clean", q' = {...q, outcome: "rejected"}}
  action RunComplete = all {Set("dirty","partial").contains(q.phase), q' = {...q, committed: q.pending, published: ResultOf(q.pending),
    generation: q.generation+1, phase: "clean", outcome: "complete"}}
  action RunBounded = all {Set("dirty","partial").contains(q.phase), q' = {...q,
    published: if (Mutation == "bounded") ResultOf(q.pending) else q.published, phase: "partial", outcome: "bounded"}}
  action RunFailure = all {Set("dirty","partial").contains(q.phase), q' = {...q, pending: q.committed, phase: "clean", outcome: "rejected"}}
  action SourceAlias = {nondet cut = Cuts.oneOf(); all {Mutation == "alias", q.phase == "clean", cut != q.committed,
    q' = {...q, committed: cut, pending: cut}}}
  action step = any {SingleReplace, BatchComplete, BatchReject, RunComplete, RunBounded, RunFailure, SourceAlias}
  val TypeOK = all {q.generation >= 0, Cuts.contains(q.committed), Cuts.contains(q.pending), q.published.subseteq(Set(1)),
    Set("clean","dirty","partial").contains(q.phase), Set("complete","provisional","bounded","rejected").contains(q.outcome)}
  val ExplorationBound = q.generation <= GenerationCutoff
  val CommittedSnapshot = q.published == ResultOf(q.committed)
  val CleanAligned = q.phase == "clean" implies q.pending == q.committed
  val PartialBounded = q.phase == "partial" implies q.outcome == "bounded"
  action privateStep = any {SingleReplace, RunBounded, BatchReject, RunFailure}
  temporal NoPrematurePublication = (privateStep implies
    (q.generation,q.committed,q.published).next() == (q.generation,q.committed,q.published)).orKeep(q).always()

}
