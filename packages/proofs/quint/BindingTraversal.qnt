// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite absorbing-fold/borrowed-loop and source-level move checks. This does
// not prove Rust's compiler, iterator, SmallVec, allocator or pointer semantics.
module BindingTraversal {
  const Mutation: str
  type Bound = {ok: bool, slots: List[int]}
  type State = {width: int, cursor: int, terms: List[int], row: List[int],
    old: Bound, owned: Bound, visits: int, failedAt: int, copies: int, published: bool}
  var q: State
  pure def Initial(width: int): List[int] = if (width == 1) List(-1)
    else if (width == 4) List(-1,-1,-1,-1) else List(-1,-1,-1,-1,-1)
  // Terms: wildcard, literal 0, literal 1, variable 0, variable last.
  pure def Apply(slots: List[int], term: int, value: int, ignore: bool): Bound =
    if (term == 0) {ok: true, slots: slots}
    else if (term < 3) {ok: value == term-1, slots: slots}
    else {
      val slot = if (term == 3) 0 else slots.length()-1
      val before = slots.nth(slot)
      {ok: before == -1 or before == value or ignore, slots: slots.replaceAt(slot,value)}
    }
  action init = {
    nondet width = Set(1,4,5).oneOf()
    nondet prior = Set(0,1,2).oneOf()
    nondet a = Set(0,1,2,3,4).oneOf()
    nondet b = Set(0,1,2,3,4).oneOf()
    nondet x = Set(0,1,2).oneOf()
    nondet y = Set(0,1,2).oneOf()
    val empty = Initial(width)
    val slots = if (prior == 0) empty else if (prior == 1) empty.replaceAt(0,0)
      else empty.replaceAt(width-1,1)
    q' = {width: width, cursor: 0, terms: List(a,b), row: List(x,y),
      old: {ok: true, slots: slots},
      owned: {ok: true, slots: if (Mutation == "erase-prior") empty else slots},
      visits: 0, failedAt: -1, copies: width, published: false}
  }
  action step = {
    val term = q.terms.nth(q.cursor)
    val value = q.row.nth(q.cursor)
    val old = if (q.old.ok) Apply(q.old.slots,term,value,false) else q.old
    val execute = (q.owned.ok or Mutation == "continue-rejected") and
      not(Mutation == "skip-last" and q.cursor == 1)
    val result = if (execute) Apply(q.owned.slots,term,value,Mutation == "ignore-conflict") else q.owned
    val owned = if (q.owned.ok) result else q.owned
    val failedAt = if (q.failedAt < 0 and not(owned.ok)) q.cursor else q.failedAt
    all {q.cursor < 2, q' = {...q, cursor: q.cursor+1, old: old, owned: owned,
      visits: q.visits + (if (execute) 1 else 0), failedAt: failedAt,
      copies: q.copies + (if (execute and Mutation == "copy-per-term") q.width else 0),
      published: q.cursor == 1 and (owned.ok or Mutation == "publish-failure")}}
  }
  val Equivalent = q.old.ok == q.owned.ok and (not(q.old.ok) or q.old.slots == q.owned.slots)
  val FailClosed = not(q.published) or q.old.ok
  val OwnedCopies = q.copies == q.width
  val StopsAtFailure = q.failedAt < 0 or q.visits == q.failedAt+1
}
