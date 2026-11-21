// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorReply {
  const Mutation: str
  val Requests = Set(1, 2)
  var admitted: Set[int]
  var posted: Set[int]
  var consumed: Set[int]
  var values: int -> int
  var authorities: int -> int
  var counts: int -> int
  var closing: bool
  var retired: bool
  var cursor: int
  var early: bool

  action init = all {
    admitted' = Set(), posted' = Set(), consumed' = Set(),
    values' = Requests.mapBy(id => 0), authorities' = Requests.mapBy(id => 0),
    counts' = Requests.mapBy(id => 0), closing' = false, retired' = false,
    cursor' = 1, early' = false
  }
  action admit = {
    nondet id = Requests.oneOf()
    all {
      not(closing), not(admitted.contains(id)), admitted' = admitted.union(Set(id)),
      posted' = posted, consumed' = consumed, values' = values,
      authorities' = authorities, counts' = counts, closing' = closing,
      retired' = retired, cursor' = if (Mutation == "cursor") 0 else cursor, early' = early
    }
  }
  action post = {
    nondet id = admitted.oneOf()
    val target = if (Mutation == "foreign") 3 - id else id
    all {
      not(retired), not(posted.contains(id)) or Mutation == "duplicate",
      posted' = posted.union(Set(target)), admitted' = admitted,
      consumed' = if (Mutation == "duplicate") consumed.exclude(Set(id)) else consumed,
      values' = values.set(target, id), authorities' = authorities.set(target, id),
      counts' = counts, closing' = closing, retired' = retired, cursor' = cursor, early' = early
    }
  }
  action take = {
    nondet id = admitted.oneOf()
    all {
      (posted.contains(id) or Mutation == "early"), not(consumed.contains(id)),
      consumed' = consumed.union(Set(id)), counts' = counts.set(id, counts.get(id) + 1),
      early' = (early or not(posted.contains(id))), admitted' = admitted,
      posted' = posted, values' = values, authorities' = authorities,
      closing' = closing, retired' = retired, cursor' = cursor
    }
  }
  action close = all {
    closing' = true, admitted' = admitted, posted' = posted, consumed' = consumed,
    values' = values, authorities' = authorities, counts' = counts,
    retired' = retired, cursor' = cursor, early' = early
  }
  action retire = all {
    closing, (admitted.subseteq(posted) or Mutation == "retire"), retired' = true,
    closing' = closing, admitted' = admitted, posted' = posted, consumed' = consumed,
    values' = values, authorities' = authorities, counts' = counts,
    cursor' = cursor, early' = early
  }
  action step = any { admit, post, take, close, retire }
  val ExactReply = consumed.forall(id => values.get(id) == id and authorities.get(id) == id)
  val Once = Requests.forall(id => counts.get(id) <= 1)
  val NoEarlyReply = not(early)
  val MailboxIsolation = cursor == 1
  val DrainedClose = not(retired) or admitted.subseteq(posted)
  val EndpointOwnership = posted.subseteq(admitted)
}
