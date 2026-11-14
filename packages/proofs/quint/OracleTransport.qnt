// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module OracleTransport {
  const Mutation: str
  pure val Channels = Set("stdout","stderr")
  pure def Expected(c: str): List[int] = if (c == "stdout") List(0,1,2) else List(7,8)
  type State = {position: str -> int, bytes: str -> List[int], closed: str -> bool, failed: str -> bool, hardError: str -> bool,
    processDone: bool, processOK: bool, requestDone: bool, requestOK: bool, admitted: bool}
  var q: State
  action init = q' = {position: Channels.mapBy(_ => 0), bytes: Channels.mapBy(_ => List()), closed: Channels.mapBy(_ => false),
    failed: Channels.mapBy(_ => false), hardError: Channels.mapBy(_ => false), processDone: false, processOK: false, requestDone: false, requestOK: false, admitted: false}
  def Live(c: str): bool = not(q.admitted) and not(q.closed.get(c)) and not(q.failed.get(c))
  action Read(c: str): bool = all {Live(c), q.position.get(c) < Expected(c).length(), q' = {...q, position: q.position.set(c,q.position.get(c)+1),
    bytes: q.bytes.set(c, if (Mutation == "tail" and q.position.get(c)+1 == Expected(c).length()) q.bytes.get(c) else q.bytes.get(c).append(Expected(c).nth(q.position.get(c))))}}
  action EOF(c: str): bool = all {Live(c), q.position.get(c) == Expected(c).length(), q' = {...q, closed: q.closed.set(c,true)}}
  action Error(c: str): bool = all {Live(c), q' = {...q, failed: q.failed.set(c,true), hardError: q.hardError.set(c,true)}}
  action Interrupt(c: str): bool = all {Live(c), q' = {...q, failed: q.failed.set(c,if (Mutation == "interrupt") true else q.failed.get(c))}}
  action Exit(ok: bool): bool = all {not(q.admitted), not(q.processDone), q' = {...q, processDone: true, processOK: ok}}
  action Send(ok: bool): bool = all {not(q.admitted), not(q.requestDone), q' = {...q, requestDone: true, requestOK: ok}}
  action Admit = all {not(q.admitted), q.processDone, q.processOK, q.requestDone, q.requestOK,
    Mutation == "early" or Channels.forall(c => q.closed.get(c) or (Mutation == "swallow" and q.failed.get(c))),
    Mutation == "swallow" or Channels.forall(c => not(q.failed.get(c))), q' = {...q, admitted: true}}
  action pipeStep = {nondet c = Channels.oneOf(); any {Read(c), EOF(c), Error(c), Interrupt(c)}}
  action step = any {Admit, Exit(true), Exit(false), Send(true), Send(false), pipeStep}
  val ReaderErrorSound = Channels.forall(c => q.failed.get(c) implies q.hardError.get(c))
  val CompleteReaders = q.admitted implies Channels.forall(c => q.closed.get(c))
  val ReaderClean = q.admitted implies Channels.forall(c => not(q.failed.get(c)))
  val CompleteBytes = q.admitted implies Channels.forall(c => q.bytes.get(c) == Expected(c))
  val ExitAndRequest = q.admitted implies (q.processDone and q.processOK and q.requestDone and q.requestOK)

}
