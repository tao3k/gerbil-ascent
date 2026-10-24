// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite canonical demand admission. Matching optimality is a separate gate.
module CanonicalIndex {
  const Mutation: str
  var demand: Set[int]
  var cursor: int
  var pending: List[int]
  var published: List[int]
  var done: bool
  val inventory = List(1,3,7,5,2,6,4)
  action init = {
    nondet selected = Set(1,2,3,4,5,6,7).powerset().oneOf()
    all { demand' = selected, cursor' = 0, pending' = List(), published' = List(), done' = false }
  }
  action collect = {
    val key = inventory.nth(cursor)
    val added = if (demand.contains(key) and not(Mutation == "omit" and key == 3))
      pending.concat(if (Mutation == "duplicate") List(key,key) else List(key)) else pending
    all {not(done), cursor < inventory.length(),
      pending' = added, cursor' = cursor + 1, demand' = demand, done' = done,
      published' = if (Mutation == "early") added else published}
  }
  action publish = all {
    not(done), cursor == inventory.length(),
    published' = if (Mutation == "order") pending.foldl(List(), (acc,key) => List(key).concat(acc)) else pending,
    done' = true, pending' = pending, cursor' = cursor, demand' = demand
  }
  action step = any { collect, publish }
  val Private = not(done) implies published == List()
  val Canonical = done implies published == inventory.foldl(List(),
    (acc,key) => if (demand.contains(key)) acc.concat(List(key)) else acc)
}
