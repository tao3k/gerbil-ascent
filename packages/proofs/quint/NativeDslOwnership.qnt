// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module NativeDslOwnership {
  const ScopeCapacity: int
  const Mutation: str
  type State = {loads: int, spent: int, live: Set[int], values: Set[int],
    definitions: int -> int, expected: int -> int, badReference: bool}
  var q: State
  action init = q' = {loads: 0, spent: 0, live: Set(), values: Set(),
    definitions: 0.to(ScopeCapacity + 1).mapBy(_ => -1),
    expected: 0.to(ScopeCapacity + 1).mapBy(_ => -1), badReference: false}
  action Load = {nondet definition = Set(0,1).oneOf(); all {
    q.loads < ScopeCapacity,
    q' = {...q, loads: q.loads + 1, spent: q.spent + 1,
      live: q.live.union(Set(q.spent)),
      definitions: if (Mutation == "scope") q.live.fold(q.definitions,
        (m,id) => m.set(id,definition)).set(q.spent,definition)
        else q.definitions.set(q.spent,definition),
      expected: q.expected.set(q.spent,definition)}}}
  // Admitted source that fails expansion still retains expander state.
  action FailedExpansion = all {q.loads < ScopeCapacity,
    q' = {...q, spent: q.spent + 1,
      loads: if (Mutation == "failed") q.loads else q.loads + 1}}
  // Authorization/reader/scaffolding rejects do not reach native expansion.
  action ReaderReject = q' = q
  action Retain = {nondet owner = q.live.oneOf(); q' = {...q, values: q.values.union(Set(owner))}}
  action Release = {nondet owner = q.values.oneOf(); q' = {...q, values: q.values.exclude(Set(owner))}}
  action Close = {nondet owner = q.live.oneOf(); q' = {...q,
    loads: if (Mutation == "reset") q.loads - 1 else q.loads,
    live: q.live.exclude(Set(owner)), values: q.values.exclude(Set(owner))}}
  action InvalidReference = {nondet owner = Set(0,1).oneOf(); nondet caller = Set(0,1).oneOf(); all {
    not(q.live.contains(caller) and q.values.contains(owner) and caller == owner),
    q' = {...q, badReference: Mutation == "foreign"}}}
  action step = any {Load, FailedExpansion, ReaderReject, Retain, Release, Close, InvalidReference}
  val ChargedExpansion = q.loads == q.spent
  val IsolatedDefinitions = q.live.forall(id => q.definitions.get(id) == q.expected.get(id))
  val NoForeignReference = not(q.badReference)
  val LiveValues = q.values.subseteq(q.live)
  // Bound IDs independently to avoid an unbounded faulty reset exploration.
  val ExplorationBound = q.spent <= ScopeCapacity + 1
}
