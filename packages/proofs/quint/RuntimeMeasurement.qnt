// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Parameterized admission policy, not measured Scheme runtime performance.
module RuntimeMeasurement {
  const PlannedCounts: Set[int]
  const MinSamples: int
  const LoadCutoff: int
  const Mutation: str

  type State = {planned: int, completed: int, fast: int, scope: int,
    checked: bool, affine: bool, drained: bool, cold: int,
    done: bool, admitted: bool}
  var q: State
  pure def Expected(s: State): bool = s.scope == 1 and
    s.completed == s.planned and s.planned >= MinSamples and
    s.checked and s.affine and s.drained and 20 * s.fast >= 19 * s.completed
  pure def Candidate(s: State): bool =
    (s.scope == 1 or Mutation == "unit") and
    (s.completed == s.planned or Mutation == "missing") and
    (s.planned >= MinSamples or Mutation == "few") and
    (s.checked or Mutation == "unchecked") and
    (s.affine or Mutation == "owner") and
    (s.drained or Mutation == "drain") and
    (20 * s.fast >= 19 * s.completed or Mutation == "tail") and
    (Mutation != "wall" or s.cold <= 1)
  action init = {
    nondet planned = PlannedCounts.oneOf()
    q' = {planned: planned, completed: 0, fast: 0,
      scope: 0, checked: true, affine: true, drained: true, cold: 0,
      done: false, admitted: false}
  }
  action Configure = {
    nondet planned = PlannedCounts.oneOf()
    nondet scope = Set(0, 1).oneOf()
    nondet checked = Set(true, false).oneOf()
    nondet affine = Set(true, false).oneOf()
    nondet drained = Set(true, false).oneOf()
    all {not(q.done), q.completed == 0,
      q' = {...q, planned: planned, scope: scope, checked: checked,
        affine: affine, drained: drained}}
  }
  action Complete = {
    nondet fast = Set(0, 1).oneOf()
    all {not(q.done), q.completed < q.planned,
      q' = {...q, completed: q.completed + 1, fast: q.fast + fast}}
  }
  action ColdLoad = q' = {...q, cold: q.cold + 1}
  action Admit = all {not(q.done), q' = {...q, done: true, admitted: Candidate(q)}}
  action step = any {Configure, Complete, ColdLoad, Admit}
  val TypeOK = PlannedCounts.contains(q.planned) and q.completed >= 0 and
    q.completed <= q.planned and q.fast >= 0 and q.fast <= q.completed
  val RuntimeExact = q.done implies (q.admitted == Expected(q))
  // Only the checker uses this finite cutoff. ColdLoad itself stays unbounded.
  val Exploration = q.cold <= LoadCutoff
}
