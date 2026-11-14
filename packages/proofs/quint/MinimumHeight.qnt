// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite min/max relaxation with shorter alternatives and source subcuts.
// -1 denotes infinity. This is not an extraction of native grounded IDs.
module MinimumHeight {
  const Mutation: str
  type State = {h: List[int], source: bool, short: bool, phase: str, work: int,
    published: List[int], publishedSource: bool, publishedShort: bool}
  var q: State
  pure val Empty = List(-1,-1,-1,-1,-1)
  pure def Expected(source: bool, short: bool): List[int] =
    if (source) List(0,1,2,if (short) 1 else 3,3) else Empty
  pure def Candidate(edge: int, h: List[int], source: bool, short: bool): int =
    if (edge == 0) {if (source) 0 else -1}
    else if (edge == 1) {if (h.nth(0) >= 0) h.nth(0)+1 else -1}
    else if (edge == 2) {if (h.nth(1) >= 0) h.nth(1)+1 else -1}
    else if (edge == 3) {if (h.nth(2) >= 0) h.nth(2)+1 else -1}
    else if (edge == 4) {if (source and short) 1 else -1}
    else if (edge == 5) {if (h.nth(3) >= 0) h.nth(3)+1 else if (Mutation == "cycle") 0 else -1}
    else {if (h.nth(1) >= 0 and h.nth(2) >= 0)
      (if (Mutation == "minimumBody") h.nth(1) else h.nth(2))+1 else -1}
  pure def EdgeHead(edge: int): int = if (edge >= 3 and edge <= 5) 3 else if (edge == 6) 4 else edge
  pure def Improves(candidate: int, old: int): bool =
    candidate >= 0 and (old < 0 or (candidate < old and Mutation != "first"))
  val Stable = Set(0,1,2,3,4,5,6).forall(edge =>
    not(Improves(Candidate(edge,q.h,q.source,q.short),q.h.nth(EdgeHead(edge)))))
  action init = {
    nondet source = Set(true,false).oneOf()
    nondet short = Set(true,false).oneOf()
    q' = {h: Empty, source: source, short: short, phase: "working", work: 0,
      published: List(), publishedSource: false, publishedShort: false}}
  action Relax = {
    nondet edge = Set(0,1,2,3,4,5,6).oneOf()
    val candidate = Candidate(edge,q.h,q.source,q.short)
    val updated = if (Improves(candidate,q.h.nth(EdgeHead(edge)))) q.h.replaceAt(EdgeHead(edge),candidate) else q.h
    all {q.phase == "working", q.work < 20,
      q' = {...q,h: updated,work: q.work+1,
        published: if (Mutation == "early") updated else q.published}}}
  action Commit = all {q.phase == "working", Stable,
    q' = {...q,phase: "idle",published: q.h,publishedSource: q.source,publishedShort: q.short}}
  action Abort = all {q.phase == "working",q' = {...q,phase: "idle"}}
  action Cut = {
    nondet cutSource = Set(true,false).oneOf()
    all {q.phase == "idle", q.source,
      q' = {...q,phase: "working",source: if (cutSource) false else q.source,
        short: false,work: 0,h: if (Mutation == "stale") q.h else Empty}}}
  action step = any {Relax,Commit,Abort,Cut}
  val CompleteMinimum = q.published == List() or
    q.published == Expected(q.publishedSource,q.publishedShort)
  val Private = q.phase != "working" or q.published == List() or
    q.published == Expected(q.publishedSource,q.publishedShort)
}
