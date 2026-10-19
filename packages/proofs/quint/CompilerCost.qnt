// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// SDK compiler correctness and native readers remain explicit external premises.
module CompilerCost {
  import CompilerPolicy.* from "./CompilerPolicy"
  const Mutation: str
  type State = {wanted: int, cached: int, valid: bool, active: bool, attempt: int,
                failed: bool, published: bool, lastGood: bool, staleReuse: bool, violation: bool}
  var q: State
  action init = q' = {wanted: 0, cached: 0, valid: false, active: false, attempt: 0,
                     failed: false, published: false, lastGood: true, staleReuse: false, violation: false}
  pure val ParentPolicy = Set(false, true).forall(same => Set(0,1,2).forall(matches => {
    val actual = if (Mutation == "cross-parent-cost") matches == 1
      else if (Mutation == "ambiguous-parent-cost") same and matches > 0
      else unique_parent_input(same, matches)
    actual == (same and matches == 1)
  }))
  pure val InputPolicy = Set(false, true).forall(is_c => Set(false, true).forall(direct => {
    val selected = compiler_input(is_c, direct)
    val actual = if (Mutation == "count-link-metadata" and is_c) true else selected
    actual == (is_c and direct)
  }))
  pure val OriginPolicy = Set([], [0], [1], [0,0], [0,1]).forall(targets =>
    Set(Set(), Set(0), Set(1), Set(0,1)).forall(arguments => {
      val actual = if (Mutation == "ignore-compiler-origin") targets == [0]
        else if (Mutation == "accept-multiple-targets") (targets == [0] or targets == [0,0]) and arguments.contains(0)
        else source_attributed(0, targets, arguments)
      actual == (targets == [0] and arguments.contains(0))
    }))
  pure val HostPolicy = Set(0, 1, 511, 512, 513, 2048).forall(labels => {
    val selected = if (Mutation == "host-boundary") labels < 512 else single_host(labels, 512)
    selected == (labels <= 512)
  })
  pure val GgcPolicy = Set(0, 1, 2).forall(expected => Set(0, 1, 2).forall(reported =>
    Set(0, 1).forall(failed => Set(0, 1).forall(changed => Set(0, 1).forall(errors => {
      val selected = ggc_complete(expected, reported,
        if (Mutation == "ignore-compiler-failure") 0 else failed,
        if (Mutation == "ignore-compiler-input") 0 else changed, errors)
      val actual = if (Mutation == "publish-partial-ggc" and expected > reported) true else selected
      actual == (0 < expected and expected == reported and failed == 0 and changed == 0 and errors == 0)
    })))))
  pure val CleanPolicy = Set(false, true).forall(current => {
    val selected = stale_modules(current, Set(0), Set(1),
      if (Mutation == "keep-unrequested-old-output") Set() else Set(0, 2))
    val actual = if (Mutation == "clean-production" and not(current)) selected.union(Set(0)) else selected
    actual == (if (current) Set() else Set(1, 2))
  })
  // Separate real GCC cumulative allocations from VM occupancy and nested pass counters.
  pure val ScopePolicy = not(Set("gcc", "vm", "rss").exists(scope =>
    (scope == "gcc" or Mutation == "promote-vm-counter") != (scope == "gcc")))
  pure val TotalPolicy = Set(0, 1, 2).forall(totals =>
    (totals == 1 or Mutation == "sum-nested-passes") == (totals == 1))
  action CheckPolicy = q' = {...q, violation: not(ParentPolicy and InputPolicy and OriginPolicy and HostPolicy and GgcPolicy and CleanPolicy and ScopePolicy and TotalPolicy)}
  action ChangeOptions = all {q.wanted < 2, q' = {...q, wanted: q.wanted + 1}}
  action Begin = all {not(q.active), q' = {...q, active: true, attempt: q.wanted, failed: false, published: false}}
  action Fail = all {q.active, q' = {...q, failed: true}}
  action Finish = all {q.active,
    val good = not(q.failed) and q.attempt == q.wanted
    val commit = good or Mutation == "record-failed-build"
    q' = {...q, active: false, valid: q.valid or commit,
      cached: if (commit) q.attempt else q.cached, published: commit, lastGood: good}}
  action Read = {
    val current = q.valid and q.cached == q.wanted
    val reuse = q.valid and (current or Mutation == "reuse-old-options")
    q' = {...q, staleReuse: q.staleReuse or (reuse and not(current))}
  }
  action step = any {CheckPolicy, ChangeOptions, Begin, Fail, Finish, Read}
  val TypeOK = q.wanted >= 0 and q.wanted <= 2 and q.cached >= 0 and q.cached <= 2
  val PolicyExact = not(q.violation)
  val CurrentOptionsOnly = not(q.staleReuse)
  val SuccessfulCommitOnly = not(q.published) or q.lastGood
}
