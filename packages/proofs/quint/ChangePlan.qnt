// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Calls interleave only at public boundaries; graph cloning is synchronous.
// OutputOf is a finite surrogate, not operator evaluation or a hash model.
module ChangePlan {
  const Mutation: str
  pure def OutputOf(capture: int, input: int): Set[int] = Set(capture, input + 2)
  type State = {source: int, owned: int, frozen: int, phase: str, input: int,
    budget: int, pending: Set[int], visible: Set[int], prior: Set[int],
    expected: Set[int], complete: bool, failed: bool}
  var q: State
  action init = q' = {source: 0, owned: -1, frozen: -1, phase: "unprepared",
    input: 0, budget: 0, pending: Set(), visible: Set(), prior: Set(),
    expected: Set(), complete: false, failed: false}
  action Prepare = all {q.phase == "unprepared",
    q' = {...q, owned: q.source, frozen: q.source, phase: "ready"}}
  action SourceEdit = all {Set("unprepared","ready").contains(q.phase),
    q' = {...q, source: 1-q.source,
      owned: if (Mutation == "alias" and q.phase == "ready") 1-q.source else q.owned}}
  action Begin = {
    nondet input = Set(0,1).oneOf()
    nondet budget = Set(1,2).oneOf()
    all {q.phase == "ready", q' = {...q, input: input, budget: budget,
      pending: Set(), prior: q.visible, phase: "working", complete: false, failed: false}}
  }
  action Solve = all {q.phase == "working",
    q' = if (q.budget == 2) {...q, pending: OutputOf(q.owned,q.input), phase: "copying", complete: true}
      else {...q, pending: Set(q.owned), phase: "ready", failed: true,
        visible: if (Mutation == "failure") Set(q.owned) else q.visible}}
  action Publish = all {q.phase == "copying" or (Mutation == "early" and q.phase == "working"),
    q' = {...q, visible: q.pending, expected: OutputOf(q.frozen,q.input), phase: "ready"}}
  action CallerEdit = all {q.phase == "ready", q.owned >= 0,
    q' = {...q, owned: if (Mutation == "borrow") 1-q.owned else q.owned}}
  action step = any {Prepare, SourceEdit, Begin, Solve, Publish, CallerEdit}
  val Frozen = q.owned == q.frozen
  val CompletePublication = q.visible == q.expected
  val FailureAtomic = q.failed implies q.visible == q.prior
}
