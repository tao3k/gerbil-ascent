// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Frozen-round semantics with independently scheduled tasks. No fairness claim:
// partial/failed executions may stop, but can never publish complete answers.
module DeltaClosure {
  const Mutation: str
  pure val Nodes = Set(0,1)
  pure val Pairs = tuples(Nodes,Nodes)
  pure val Triples = tuples(Nodes,Nodes,Nodes)
  pure def Join(rows: Set[(int,int)]): Set[(int,int)] =
    Triples.filter(t => rows.contains((t._1,t._2)) and rows.contains((t._2,t._3))).map(t => (t._1,t._3))
  pure def Close(edges: Set[(int,int)]): Set[(int,int)] = Nodes.fold(edges,(rows,b) =>
    rows.union(Pairs.filter(p => rows.contains((p._1,b)) and rows.contains((b,p._2)))))
  type State = {edges: Set[(int,int)], p: Set[(int,int)], q: Set[(int,int)],
    dp: Set[(int,int)], dq: Set[(int,int)], np: Set[(int,int)], nq: Set[(int,int)],
    queued: Set[int], active: Set[int], finished: Set[int], assigned: Set[int],
    complete: bool, failed: bool, first: bool, oldWork: int, duplicate: bool,
    visibleP: Set[(int,int)], visibleQ: Set[(int,int)]}
  var s: State
  action init = { nondet edges = Pairs.powerset().oneOf()
    s' = {edges: edges, p:Set(), q:Set(), dp:Set(), dq:Set(), np:Set(), nq:Set(),
      queued:Set(0,1,2), active:Set(), finished:Set(), assigned:Set(0,1,2),
      complete:false, failed:false, first:true, oldWork:0, duplicate:false, visibleP:Set(), visibleQ:Set()} }
  pure def Witnesses(rows: Set[(int,int)]): Set[(int,int,int)] =
    Triples.filter(t => rows.contains((t._1,t._2)) and rows.contains((t._2,t._3)))
  action Dispatch(task: int): bool = all {not(s.complete), not(s.failed), s.queued.contains(task),
    s' = {...s, queued:s.queued.exclude(Set(task)), active:s.active.union(Set(task))}}
  action Finish(task: int): bool = {
    val witnesses = Witnesses(s.q)
    val left = witnesses.filter(t => s.dq.contains((t._1,t._2)))
    val right = witnesses.filter(t => s.dq.contains((t._2,t._3)) and
      (Mutation == "overlap" or not(s.dq.contains((t._1,t._2)))))
    val selected = if (s.first or Mutation == "allold") witnesses else left.union(right)
    val outputs = if (task == 0) s.edges else if (task == 1) selected.map(t => (t._1,t._3)) else s.p
    all {not(s.complete), not(s.failed), s.active.contains(task),
      s' = {...s, active:s.active.exclude(Set(task)), finished:s.finished.union(Set(task)),
        np:if (task == 2) s.np else s.np.union(outputs.exclude(s.p)),
        nq:if (task == 2) s.nq.union((if (s.first) outputs else s.dp).exclude(s.q)) else s.nq,
        complete:Mutation == "early" and task == 0,
        duplicate:s.duplicate or (not(s.first) and task == 1 and left.intersect(right) != Set()),
        oldWork:s.oldWork + (if (not(s.first) and task == 1)
          selected.filter(t => not(s.dq.contains((t._1,t._2))) and not(s.dq.contains((t._2,t._3)))).size() else 0)}}
  }
  action Commit = {
    val nextP = s.p.union(s.np)
    val nextQ = s.q.union(s.nq)
    val scheduled = (if (s.nq != Set()) Set(1) else Set()).union(
      if (s.np != Set() and Mutation != "drop") Set(2) else Set())
    val closed = s.np == Set() and s.nq == Set()
    all {not(s.complete), not(s.failed), s.queued == Set(), s.active == Set(),
      s' = {...s, p:nextP, q:nextQ, dp:s.np, dq:s.nq, np:Set(), nq:Set(), first:false,
        complete:closed or (Mutation == "drop" and scheduled == Set()),
        queued:scheduled, assigned:scheduled, finished:Set(),
        visibleP:if (closed) nextP else s.visibleP, visibleQ:if (closed) nextQ else s.visibleQ}}
  }
  // Cancellation and exhausted resources share the fail-closed admission edge.
  action Refuse = all {not(s.complete), not(s.failed), s' = {...s, failed:true}}
  action taskStep = { nondet task = Set(0,1,2).oneOf(); any {Dispatch(task),Finish(task)} }
  action step = any {taskStep, Commit, Refuse}
  val Complete = s.complete implies all {s.p == Close(s.edges), s.q == s.p,
    s.queued == Set(), s.active == Set(), s.np == Set(), s.nq == Set()}
  val Partition = all {s.queued.union(s.active).union(s.finished) == s.assigned,
    s.queued.intersect(s.active) == Set(), s.active.intersect(s.finished) == Set(), s.queued.intersect(s.finished) == Set()}
  val FrontierExact = s.dp.subseteq(s.p) and s.dq.subseteq(s.q) and
    s.np.intersect(s.p) == Set() and s.nq.intersect(s.q) == Set()
  val NoOldWork = s.oldWork == 0
  val UniqueWitness = not(s.duplicate)
  val FailurePrivate = s.failed implies (not(s.complete) and s.visibleP == Set() and s.visibleQ == Set())
}
