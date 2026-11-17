// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorSession {
  const Cuts: Set[int]
  const GenerationCutoff: int
  const Mutation: str
  type State = {generation: int, epoch: int, pending: int, committed: int, published: Set[int], publishedCut: int,
    frozen: int, phase: str, assigned: bool, closing: bool, stalePublish: bool, earlyClose: bool,
    retained: bool, retainedCut: int, eligible: bool, wrongReuse: bool,
    creationAllowed: bool, requestAllowed: bool, finalAllowed: bool, wrongAuthority: bool,
    badPartial: bool, replacing: bool, priorCut: int}
  var q: State
  pure def Result(cut: int): Set[int] = Set(cut)
  action init = q' = {generation: 0, epoch: 0, pending: 0, committed: 0, published: Result(0), publishedCut: 0,
    frozen: 0, phase: "idle", assigned: false, closing: false, stalePublish: false, earlyClose: false,
    retained: false, retainedCut: 0, eligible: false, wrongReuse: false,
    creationAllowed: true, requestAllowed: true, finalAllowed: true, wrongAuthority: false,
    badPartial: false, replacing: false, priorCut: 0}
  action Update = {nondet cut = Cuts.oneOf(); all {q.phase == "idle", not(q.closing), q' = {...q, pending: cut, retained: if (Mutation == "changed-reuse") q.retained else false, generation: q.generation + 1}}}
  action Start = {
    nondet eligible = Set(true, false).oneOf()
    nondet requestAllowed = Set(true, false).oneOf()
    nondet finalAllowed = Set(true, false).oneOf()
    all {q.phase == "idle", not(q.closing), q' = {...q,
      generation: q.generation + 1, epoch: q.generation + 1, frozen: q.pending,
      phase: "running", assigned: true, requestAllowed: requestAllowed, finalAllowed: finalAllowed,
      eligible: eligible,
      wrongReuse: q.wrongReuse or (q.retained and
        (eligible or Mutation == "opaque-reuse") and
        (not(eligible) or q.retainedCut != q.pending))}}
  }
  action Replace = {
    nondet proposed = Cuts.oneOf()
    nondet requestAllowed = Set(true, false).oneOf()
    nondet finalAllowed = Set(true, false).oneOf()
    all {q.phase == "idle", not(q.closing), q.pending == q.committed,
      q' = {...q, generation: q.generation + 1, epoch: q.generation + 1,
        pending: if (Mutation == "eager-pending") proposed else q.pending,
        priorCut: q.pending, frozen: proposed, retained: false,
        phase: "running", assigned: true, replacing: true, eligible: true,
        requestAllowed: requestAllowed, finalAllowed: finalAllowed}}
  }
  action RetireCreation = all {q.creationAllowed, q' = {...q, creationAllowed: false}}
  action Cancel = all {Set("running", "draining").contains(q.phase), q' = {...q, generation: q.generation + 1, phase: "draining"}}
  action Finish(success: bool): bool = {
    val expected = success and q.epoch == q.generation and q.requestAllowed and q.finalAllowed
    val published = success and (q.epoch == q.generation or Mutation == "stale") and
      (if (Mutation == "creation-authority") q.creationAllowed else q.requestAllowed) and
      (q.finalAllowed or Mutation == "final-authority")
    all {q.assigned, Set("running", "draining").contains(q.phase),
    q' = if (published)
      {...q, published: Result(q.frozen), publishedCut: q.frozen, committed: q.frozen,
        pending: q.frozen, replacing: false,
        stalePublish: q.stalePublish or q.epoch != q.generation, assigned: false, phase: "idle",
        retained: q.eligible, retainedCut: q.frozen,
        wrongAuthority: q.wrongAuthority or published != expected}
    else {...q, pending: q.committed, assigned: false, phase: "idle", replacing: false,
        retained: false,
        wrongAuthority: q.wrongAuthority or published != expected}}
  }
  action Pause = {
    val expected = q.epoch == q.generation and q.requestAllowed
    val delivery = (q.epoch == q.generation or Mutation == "stale-partial") and q.requestAllowed
    val publish = delivery and Mutation == "partial-publication"
    all {q.assigned, not(q.replacing), Set("running", "draining").contains(q.phase),
      q' = {...q, phase: "idle", assigned: false,
        pending: if (delivery) q.pending else q.committed,
        retained: delivery and q.eligible, retainedCut: q.frozen,
        committed: if (publish) q.frozen else q.committed,
        publishedCut: if (publish) q.frozen else q.publishedCut,
        published: if (publish) Result(q.frozen) else q.published,
        badPartial: q.badPartial or publish or delivery != expected}}
  }
  action RequestClose = all {q.phase != "closed", not(q.closing), q' = {...q, closing: true,
    generation: if (q.assigned) q.generation + 1 else q.generation, phase: if (q.assigned) "draining" else q.phase}}
  action Close = all {q.closing, q.phase != "closed", not(q.assigned) or Mutation == "early", q' = {...q, phase: "closed", earlyClose: q.earlyClose or q.assigned}}
  action step = any {Update, Start, Replace, Cancel, Finish(true), Finish(false), Pause, RequestClose, Close, RetireCreation}
  val ConsistentPublication = q.published == Result(q.publishedCut) and q.committed == q.publishedCut
  val NoStalePublication = not(q.stalePublish)
  val DrainedClose = not(q.earlyClose) and (q.phase == "closed" implies not(q.assigned))
  val ReuseExact = not(q.wrongReuse)
  val AuthorityExact = not(q.wrongAuthority)
  val PartialPrivate = not(q.badPartial)
  val ReplacementPrivate = q.replacing implies (q.pending == q.priorCut and q.committed == q.priorCut)
  // Only the checker configuration references this predicate; step is unbounded.
  val Exploration = q.generation <= GenerationCutoff

}
