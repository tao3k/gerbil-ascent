// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorCutEligibility {
  const Mutation: str
  type State = {initial: List[bool], cut: List[bool], flags: List[bool],
    canonical: bool, currentMetadata: bool, trusted: bool,
    replaced: bool, checked: bool, retain: bool}
  var q: State

  pure def scalar(slots: List[bool]): bool = slots.foldl(true, (allScalar, slot) => allScalar and slot)

  action init = {
    nondet first = Set(true, false).oneOf()
    nondet other = Set(true, false).oneOf()
    nondet canonical = Set(true, false).oneOf()
    nondet currentMetadata = Set(true, false).oneOf()
    nondet trusted = Set(true, false).oneOf()
    val captured = List(first, other)
    q' = {initial: captured, cut: captured, flags: captured,
      canonical: canonical, currentMetadata: currentMetadata, trusted: trusted,
      replaced: false, checked: false, retain: false}
  }

  action replace = {
    nondet nextScalar = Set(true, false).oneOf()
    val captured = List(nextScalar, q.cut.nth(1))
    all {
      not(q.replaced), not(q.checked),
      q' = {...q, cut: captured, replaced: true,
        flags: if (Mutation == "stale-flag") q.flags else captured}
    }
  }

  action decideReuse = {
    val inspect = if (Mutation == "inspect-initial") q.initial else q.flags
    all {
      not(q.checked),
      q' = {...q, checked: true,
        retain: (q.canonical or Mutation == "foreign-cut")
          and (q.currentMetadata or Mutation == "skip-metadata")
          and (q.trusted or Mutation == "skip-protocol") and scalar(inspect)}
    }
  }

  action step = any {replace, decideReuse}
  val ExactCut = q.flags == q.cut
  val EligibilityExact = not(q.checked) or
    (q.retain == (q.canonical and q.currentMetadata and q.trusted and scalar(q.cut)))
}
