// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorCompactResult {
  const Mutation: str
  type State = {phase: str, room: int, current: int, assigned: int,
    reported: int, result: List[int], canceled: bool}
  var q: State

  val old = List(8)
  val emitted = List(12, 1, 23, 13)
  val exact = List(13, 23, 1, 12)

  action init = {
    nondet room = 3.to(5).oneOf()
    q' = {phase: "worker", room: room, current: 1, assigned: 1,
      reported: 0, result: old, canceled: false}
  }
  action finish = {
    val count = emitted.length()
    val reported = if (Mutation == "underreport") count - 1 else count
    all {
      q.phase == "worker",
      q' = {...q, reported: reported, phase:
        if (reported <= q.room or Mutation == "adopt-over-budget") "joined" else "fallback"}
    }
  }
  action cancel = all {
    q.phase == "worker" or q.phase == "joined",
    not(q.canceled),
    q' = {...q, canceled: true, current: q.current + 1}
  }
  action publish = all {
    q.phase == "joined",
    if (q.current == q.assigned or Mutation == "publish-stale")
      q' = {...q, phase: "published", result: if (Mutation == "keep-emission-order") emitted else exact}
    else q' = {...q, phase: "rejected"}
  }
  action step = any {finish, cancel, publish}

  val ExactCount = q.phase != "joined" or q.reported == emitted.length()
  val Budget = q.phase != "joined" or q.reported <= q.room
  val OwnerOnly = q.phase != "published" or (not(q.canceled) and q.current == q.assigned)
  val ExactExport = q.phase != "published" or q.result == exact
  val PrivateUntilPublish = q.phase == "published" or q.result == old
}
