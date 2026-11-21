// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorResidentWorker {
  const Mutation: str
  type State = {generation: int, epoch: int, phase: str,
    resident: bool, closing: bool, reaped: bool, badSender: bool,
    stalePublish: bool, staleFallback: bool, earlyClose: bool}
  var q: State

  action init = q' = {generation: 0, epoch: 0, phase: "idle",
    resident: false, closing: false, reaped: false, badSender: false,
    stalePublish: false, staleFallback: false, earlyClose: false}

  action admit = all {
    q.phase == "idle", not(q.closing), q.generation < 4,
    q' = {...q, generation: q.generation + 1, epoch: q.generation + 1,
      phase: "resident", resident: true}
  }

  action invalidate = all {
    q.phase == "resident" or q.phase == "ordinary",
    q.generation == q.epoch,
    q' = {...q, generation: q.generation + 1}
  }

  action reply = {
    nondet ownsRun = Set(true, false).oneOf()
    nondet declined = Set(true, false).oneOf()
    val current = q.epoch == q.generation
    val accept = ownsRun or Mutation == "accept-retired-worker"
    val fallback = declined and (current or Mutation == "fallback-canceled")
    val publish = not(declined) and (current or Mutation == "publish-canceled")
    all {
      q.phase == "resident",
      q' = if (accept)
        {...q, phase: if (fallback) "ordinary" else "idle",
          badSender: q.badSender or not(ownsRun),
          stalePublish: q.stalePublish or (publish and not(current)),
          staleFallback: q.staleFallback or (fallback and not(current))}
        else q
    }
  }

  action workerExit = all {
    q.resident,
    q' = {...q, resident: false, phase: if (q.phase == "resident") "idle" else q.phase}
  }

  action ordinaryFinish = all {
    q.phase == "ordinary",
    q' = {...q, phase: "idle"}
  }

  action requestClose = all {
    not(q.closing),
    q' = {...q, closing: true,
      generation: if (q.phase == "idle") q.generation else q.generation + 1}
  }

  action finishClose = all {
    q.closing, q.phase != "closed",
    q.phase == "idle" or Mutation == "close-with-job",
    q' = {...q, phase: "closed", resident: false,
      reaped: not(q.resident) or Mutation != "skip-join",
      earlyClose: q.phase != "idle"}
  }

  action step = any {admit, invalidate, reply, workerExit, ordinaryFinish,
    requestClose, finishClose}
  val SenderOwnsRun = not(q.badSender)
  val CurrentPublication = not(q.stalePublish)
  val CurrentFallback = not(q.staleFallback)
  val DrainedBeforeClose = not(q.earlyClose)
  val ClosedWorkerJoined = q.phase != "closed" or q.reaped
}
