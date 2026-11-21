// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorTerminalCommit {
  const Mutation: str
  val oldRows = List(9, 9)
  val newRows = List(1, 0, 2)
  type State = {stage: int, privateLane: List[int], published: List[int],
    derivedRoom: int, outputRoom: int, laterReader: bool, ownsLane: bool, resumed: bool,
    canceled: bool, reusedLane: bool, failure: str, ownerAccepted: bool}
  var q: State

  action init = {
    nondet derivedRoom = Set(0, 2, 3).oneOf()
    nondet outputRoom = Set(0, 2, 3).oneOf()
    nondet laterReader = Set(true, false).oneOf()
    nondet ownsLane = Set(true, false).oneOf()
    nondet resumed = Set(true, false).oneOf()
    q' = {stage: 0, privateLane: List(), published: oldRows,
      derivedRoom: derivedRoom, outputRoom: outputRoom,
      laterReader: laterReader, ownsLane: ownsLane, resumed: resumed, canceled: false,
      reusedLane: false, failure: "", ownerAccepted: false}
  }
  action Stage = {
    val derivedFirst = q.derivedRoom < q.outputRoom
      or (q.derivedRoom == q.outputRoom and Mutation != "wrong-priority")
    val room = if (derivedFirst or Mutation == "ignore-output") q.derivedRoom else q.outputRoom
    all {
      q.stage == 0,
      q' = {...q, stage: 1, privateLane: newRows.slice(0, room),
        failure: if (room >= newRows.length()) "" else if (derivedFirst) "derived" else "output"}
    }
  }
  action Cancel = all {q.stage < 3, not(q.canceled), q' = {...q, canceled: true}}
  action Commit = all {
    q.stage == 1,
    q' = {...q, stage: 2,
      reusedLane: q.failure == "" and (not(q.laterReader) or Mutation == "later-reader")
        and (q.ownsLane or Mutation == "borrowed-lane")
        and (not(q.resumed) or Mutation == "resume")}
  }
  action Return = {
    nondet accept = Set(true, false).oneOf()
    val lane = if (q.reusedLane and Mutation == "wrong-order") List(2, 0, 1) else q.privateLane
    all {
      q.stage == 2,
      q' = {...q, stage: 3, ownerAccepted: accept,
        published: if ((q.failure == "" or Mutation == "ignore-budget")
                       and (not(q.canceled) or Mutation == "ignore-cancel")
                       and (accept or Mutation == "ignore-owner")) lane.concat(oldRows) else oldRows}
    }
  }
  action step = any {Stage, Cancel, Commit, Return}
  val OwnsReusableLane = not(q.reusedLane) or q.ownsLane
  val NoLaterReader = not(q.reusedLane) or (not(q.laterReader) and not(q.resumed))
  val ExactFactLimit = q.stage == 0 or (
    val accepted = newRows.foldl(List(), (rows, row) =>
      if (rows.length() < q.derivedRoom and rows.length() < q.outputRoom) rows.append(row) else rows)
    val firstRejected = accepted.length() + 1
    q.privateLane == accepted and q.failure == (if (firstRejected > newRows.length()) ""
      else if (firstRejected > q.derivedRoom) "derived" else "output")
  )
  val ExactPublication = q.published ==
    (if (q.stage == 3 and q.ownerAccepted and q.failure == "" and not(q.canceled))
       newRows.concat(oldRows) else oldRows)
}
