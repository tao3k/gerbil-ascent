// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RectangleExport {
  const Mutation: str
  type Row = List[int]
  pure def Reverse(xs: List[a]): List[a] = xs.foldl(List(), (acc,x) => List(x).concat(acc))
  // Multiple descriptor orders, empty axes and false-like group value 0.
  pure val Cuts = Set(List(), List(List(0,1),List(0,2),List(1,1),List(1,2)),
    List(List(0,0,1),List(0,0,2),List(0,1,1),List(0,1,2)),
    List(List(0,1),List(0,2),List(7,2,0)))
  type State = {cut: List[Row], held: List[Row], public: List[Row], sibling: List[Row],
    captured: bool, exported: bool, modified: bool}
  var q: State
  action init = q' = {cut: List(), held: List(), public: List(), sibling: List(),
    captured: false, exported: false, modified: false}
  action Capture = {nondet cut = Cuts.oneOf(); all {not(q.captured),
    q' = {...q, cut: cut, held: cut, captured: true}}}
  action Export = all {q.captured, not(q.exported), q' = {...q,
    public: if (Mutation == "order") Reverse(q.cut) else q.cut,
    sibling: q.cut, exported: true}}
  action Mutate = all {q.exported, not(q.modified), q.public.length() > 0,
    q' = {...q, public: List(List(99)), modified: true,
      cut: if (Mutation == "alias") List(List(99)) else q.cut,
      sibling: if (Mutation == "shared") List(List(99)) else q.sibling}}
  action step = any {Capture, Export, Mutate}
  val FrozenExact = q.cut == q.held
  val OrderedExact = q.exported and not(q.modified) implies q.public == q.held
  val IndependentReads = q.exported implies q.sibling == q.held
  val CountExact = q.exported and not(q.modified) implies q.public.length() == q.held.length()
}
