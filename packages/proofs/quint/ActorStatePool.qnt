// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorStatePool {
  const Mutation: str
  type State = {idle: List[int], borrowed: Set[int], abandoned: Set[int],
    next: int, rejected: bool}
  var q: State

  val capacity = 2
  action init = q' = {idle: List(), borrowed: Set(),
    abandoned: Set(), next: 0, rejected: false}

  action borrow = {
    val empty = q.idle.length() == 0
    val endpoint = if (empty) q.next else q.idle.head()
    all {
      not(empty) or q.next < 4,
      q' = if (empty and Mutation == "reject-on-miss")
        {...q, rejected: true}
        else {...q, borrowed: q.borrowed.union(Set(endpoint)),
          idle: if (empty or Mutation == "leave-taken") q.idle else q.idle.tail(),
          next: if (empty) q.next + 1 else q.next}
    }
  }

  action complete = {
    nondet endpoint = q.borrowed.oneOf()
    q' = {...q, borrowed: q.borrowed.exclude(Set(endpoint)),
      idle: if (q.idle.length() < capacity or Mutation == "retain-overflow")
        List(endpoint).concat(q.idle) else q.idle}
  }

  action abandon = {
    nondet endpoint = q.borrowed.oneOf()
    q' = {...q, borrowed: q.borrowed.exclude(Set(endpoint)),
      abandoned: q.abandoned.union(Set(endpoint)),
      idle: if (Mutation == "retain-abandoned") List(endpoint).concat(q.idle) else q.idle}
  }

  action step = any {borrow, complete, abandon}

  val DisjointLease = q.idle.indices().forall(i => not(q.borrowed.contains(q.idle.nth(i))))
  val IdleUnique = q.idle.indices().forall(i =>
    q.idle.indices().forall(j => i == j or q.idle.nth(i) != q.idle.nth(j)))
  val RetentionBound = q.idle.length() <= capacity
  val NoAbandonedReuse = q.idle.indices().forall(i => not(q.abandoned.contains(q.idle.nth(i))))
  val MissDoesNotReject = not(q.rejected)
}
