// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module EvidenceLifecycle {
  const GenerationCutoff: int
  const InputLimit: int
  const Mutation: str
  // Masks represent a two-value source domain, NOT a runtime cardinality cap.
  pure def count(mask: int): int = mask % 2 + mask / 2
  pure def admitted(mask: int, limit: int): bool = limit == 0 or count(mask) <= limit
  type State = {alive: bool, generation: int, source: int,
    resultLive: bool, resultGeneration: int, resultRows: int,
    proofHeld: bool, proofOwned: bool, proofGeneration: int,
    proofRows: int, proofOrigin: int, rejected: bool, rejectedSource: int}
  pure def initial(mask: int): State = {alive: true, generation: 0, source: mask,
    resultLive: false, resultGeneration: -1, resultRows: 0,
    proofHeld: false, proofOwned: false, proofGeneration: -1,
    proofRows: 0, proofOrigin: 0, rejected: false, rejectedSource: mask}
  // Event IDs: run, explain, release-result, replace, reject-batch,
  // release-explanation, close, repeat-run. This is a protocol transition
  // relation; neither this model nor Python evaluates arbitrary Scheme.
  pure def advance(s: State, event: int, replacement: int, fault: str): State = {
    val base = {...s, rejected: false}
    if (event == 0) {...base, resultLive: true, resultGeneration: s.generation, resultRows: s.source}
    else if (event == 1) {...base, proofHeld: true, proofOwned: true,
      proofGeneration: s.generation, proofRows: s.resultRows, proofOrigin: s.resultRows}
    else if (event == 2) {...base, resultLive: false,
      proofOwned: if (fault == "coupled") false else s.proofOwned}
    else if (event == 3) {...base, source: replacement, generation: s.generation + 1,
      resultLive: fault == "stale" and s.resultLive, proofOwned: false,
      proofRows: if (fault == "rewrite" and s.proofHeld) replacement else s.proofRows}
    else if (event == 4) {...base, rejected: true, rejectedSource: s.source,
      source: if (fault == "reject") (s.source + 1) % 4 else s.source}
    else if (event == 5) {...base, proofHeld: false, proofOwned: false}
    else if (event == 6) {...base, alive: false,
      resultLive: fault == "close" and s.resultLive, proofHeld: false, proofOwned: false}
    else base
  }
  var q: State
  action init = {nondet mask = Set(0,1,2,3).oneOf(); all {
    admitted(mask, InputLimit), q' = initial(mask)}}
  action Run = all {q.alive, not(q.resultLive), q' = advance(q, 0, 0, Mutation)}
  action Explain = all {q.alive, q.resultLive, not(q.proofHeld), q' = advance(q, 1, 0, Mutation)}
  action ReleaseResult = all {q.alive, q.resultLive, q' = advance(q, 2, 0, Mutation)}
  action Replace = {nondet mask = Set(0,1,2,3).oneOf(); all {
    q.alive, admitted(mask, InputLimit), q' = advance(q, 3, mask, Mutation)}}
  action RejectBatch = all {q.alive, q' = advance(q, 4, 0, Mutation)}
  action ReleaseProof = all {q.alive, q.proofHeld, q' = advance(q, 5, 0, Mutation)}
  action Close = all {q.alive, q' = advance(q, 6, 0, Mutation)}
  action RepeatRun = all {q.alive, q.resultLive, q' = advance(q, 7, 0, Mutation)}
  action step = any {Run, Explain, ReleaseResult, Replace, RejectBatch, ReleaseProof, Close, RepeatRun}
  val TypeOK = all {q.generation >= 0, Set(0,1,2,3).contains(q.source), admitted(q.source, InputLimit)}
  val CurrentResult = q.resultLive implies all {q.alive, q.resultGeneration == q.generation, q.resultRows == q.source}
  val IndependentExplanation = (q.alive and q.proofHeld and q.proofGeneration == q.generation) implies q.proofOwned
  val FrozenObservation = q.proofHeld implies q.proofRows == q.proofOrigin
  val RejectionAtomic = q.rejected implies q.source == q.rejectedSource
  val ClosedOwners = not(q.alive) implies not(q.resultLive or q.proofHeld or q.proofOwned)
  // Only TLC's constraint uses the cutoff. Runtime generations are unbounded.
  val ExplorationBound = q.generation <= GenerationCutoff

  pure def observation(s: State): List[int] = List(
    if (s.alive) 1 else 0, s.generation, s.source,
    if (s.resultLive) 1 else 0, if (s.proofHeld) 1 else 0,
    if (s.proofOwned) 1 else 0, s.proofGeneration, s.proofRows)
  pure def replay(mask: int, replacement: int, events: List[int]): List[List[int]] = {
    val states = events.foldl(List(initial(mask)), (states, event) =>
      states.append(advance(states.nth(states.length()-1), event, replacement, "none")))
    states.foldl(List(), (observations,s) => observations.append(observation(s)))
  }
  pure val conformance = range(0,32).foldl(List(), (traces, n) => {
    val before = n % 16 / 4
    val after = n % 4
    val events = List(0,7,1,3,4,0,2,5,6)
    val independent = List(0,1,2,3,4,0,2,5,6)
    if (not(admitted(before,n/16) and admitted(after,n/16))) traces else
    traces.append(List(List(n / 16,before,after),events).concat(replay(before,after,events)))
      .append(List(List(n / 16,before,after),independent).concat(replay(before,after,independent)))
  })
}
