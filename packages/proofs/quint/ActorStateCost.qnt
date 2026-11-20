// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite source-cost controls, not a model of the native collector or scheduler.
module ActorStateCost {
  const Mutation: str
  type State = {phase: int, completed: int, endpoints: int, envelopePairs: int,
    statePairs: int, outcomes: int, clockBuffers: int, timed: bool,
    wall: int, cpu: int, gcWall: int, gcCpu: int, pauses: int, collections: int,
    reported: bool, reportedWall: int, cursor: int}
  var q: State

  action init = {
    nondet timed = Set(false, true).oneOf()
    q' = {phase: 0, completed: 0, endpoints: 0, envelopePairs: 0,
      statePairs: 0, outcomes: 0, clockBuffers: 0, timed: timed,
      wall: 0, cpu: 0, gcWall: 0, gcCpu: 0, pauses: 0, collections: 0,
      reported: false, reportedWall: 0, cursor: 1}
  }
  action Allocate = all {not(q.reported), q.phase == 0, q.completed < 2,
    q' = {...q, phase: 1, endpoints: q.endpoints +
      (if (Mutation == "reuse-endpoint" and q.completed > 0) 0 else 1),
      wall: q.wall + 1, cpu: q.cpu + 1}}
  action Send = all {not(q.reported), q.phase == 1,
    q' = {...q, phase: 2,
      envelopePairs: q.envelopePairs + (if (Mutation == "hide-envelope") 0 else 5),
      cursor: if (Mutation == "caller-cursor") 0 else q.cursor,
      wall: q.wall + 1, cpu: q.cpu + 1}}
  action OwnerReply = all {not(q.reported), q.phase == 2,
    q' = {...q, phase: 3,
      statePairs: q.statePairs + (if (Mutation == "hide-state-pairs") 0 else 2),
      outcomes: q.outcomes + (if (Mutation == "hide-outcome") 0 else 1),
      wall: q.wall + 1, cpu: q.cpu + 1}}
  action Take = all {not(q.reported), q.phase == 3,
    q' = {...q, phase: 0, completed: q.completed + 1,
      clockBuffers: q.clockBuffers +
        (if (q.timed and Mutation != "hide-clock") 2 else 0),
      wall: q.wall + 1, cpu: q.cpu + 1}}
  // Delays and collections do not alter the logical request or erase work.
  action Pause = all {not(q.reported), q.pauses < 2,
    q' = {...q, pauses: q.pauses + 1, wall: q.wall + 1}}
  action Collect = all {not(q.reported), q.collections < 2,
    q' = {...q, collections: q.collections + 1, wall: q.wall + 1,
      cpu: q.cpu + 1, gcWall: q.gcWall + 1, gcCpu: q.gcCpu + 1}}
  action Report = all {not(q.reported), q.completed == 2,
    q' = {...q, reported: true,
      reportedWall: if (Mutation == "subtract-gc") q.wall - q.gcWall
        else if (Mutation == "report-cpu-as-wall") q.cpu else q.wall}}
  action step = any {Allocate, Send, OwnerReply, Take, Pause, Collect, Report}

  val FreshEndpoints = q.endpoints == q.completed + (if (q.phase > 0) 1 else 0)
  val EnvelopeExact = q.envelopePairs == 5 * (q.completed + (if (q.phase >= 2) 1 else 0))
  val StateExact = q.statePairs == 2 * (q.completed + (if (q.phase == 3) 1 else 0))
  val OutcomeExact = q.outcomes == q.completed + (if (q.phase == 3) 1 else 0)
  val ClockExact = q.clockBuffers == (if (q.timed) 2 * q.completed else 0)
  val MailboxIsolation = q.cursor == 1
  val ClockBounds = q.cpu <= q.wall and q.gcCpu <= q.cpu and q.gcWall <= q.wall
  val NoDiscountedWall = not(q.reported) or q.reportedWall == q.wall
}
