// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module WeightedExport {
  const Mutation: str
  type Row = (int,int)
  type Block = (List[int],List[int])
  pure def Reverse(xs: List[a]): List[a] = xs.foldl(List(), (acc,x) => List(x).concat(acc))
  pure def Product(b: Block): List[Row] = b._1.foldl(List(), (acc,x) =>
    acc.concat(b._2.foldl(List(), (ys,y) => ys.append((x,y)))))
  pure def ProductRows(bs: List[Block]): List[Row] = bs.foldl(List(), (acc,b) => acc.concat(Product(b)))
  pure def Collect(bs: List[Block]): List[Row] = bs.foldl(List(), (acc,b) =>
    b._1.foldl(acc, (rows,x) => b._2.foldl(rows, (rows,y) => rows.append((x,y)))))
  pure def Has(xs: List[int], key: int): bool = xs.foldl(false, (found,x) => found or x == key)
  pure def Axis(bs: List[Block], axis: int, key: int): List[Row] =
    bs.foldl(List(), (acc,b) => acc.concat(Product(
      if (axis == 0) (if (Has(b._1,key)) List(key) else List(), b._2)
      else (b._1, if (Has(b._2,key)) List(key) else List()))))
  // The implementation shares admitted axis selection with row visitors,
  // then collects entire products without a callback for each public tuple.
  pure def SelectedBlocks(bs: List[Block], axis: int, key: int): List[Block] =
    bs.foldl(List(), (acc,b) => acc.append(
      if (axis == 0) (b._1.foldl(List(), (xs,x) => if (x == key) xs.append(x) else xs), b._2)
      else (b._1, b._2.foldl(List(), (ys,y) => if (y == key) ys.append(y) else ys))))
  pure def SelectedCollect(bs: List[Block], axis: int, key: int): List[Row] =
    Collect(if (Mutation == "selected-order") Reverse(SelectedBlocks(bs,axis,key))
      else SelectedBlocks(bs,axis,key))
  pure def Select(rows: List[Row], axis: int, key: int): List[Row] =
    rows.foldl(List(), (acc,p) => if ((if (axis == 0) p._1 else p._2) == key) acc.append(p) else acc)
  pure def SelfAxes(bs: List[Block]): bool = bs.foldl(true, (ok,b) => ok and b._1 == b._2)
  pure def SharedLeft(bs: List[Block], key: int): List[Row] = bs.foldl(List(), (acc,b) =>
    if (Has(b._2,key)) acc.concat(Product(if (Mutation == "plan-axis") (b._1,List(key)) else (List(key),b._2))) else acc)
  type State = {blocks: List[Block], held: List[Row], public: List[Row], sibling: List[Row],
    count: int, phase: str, retired: bool, mutated: bool, ready: Set[int], reads: int -> List[Row]}
  var q: State
  action init = q' = {blocks: List(), held: List(), public: List(), sibling: List(),
    count: 0, phase: "new", retired: false, mutated: false, ready: Set(), reads: Map(0 -> List(), 1 -> List())}
  action Capture = {
    nondet left = Set(List(0,1), List(1,0), List()).oneOf()
    nondet right = Set(List(0,2), List(2,1), List()).oneOf()
    nondet mode = Set("normal","self").oneOf()
    val blocks = if (mode == "self") List((left,left),(right,right)) else List((left,right),(List(2),List(0,1)))
    all {q.phase == "new", q' = {...q, blocks: blocks, held: ProductRows(blocks), count: if (Mutation == "mass") blocks.length()
      else blocks.foldl(0, (total,b) => total + b._1.length() * b._2.length()), phase: "captured"}}
  }
  action Export = {
    val rows = if (Mutation == "order") Reverse(Collect(q.blocks)) else Collect(q.blocks)
    all {q.phase == "captured", q' = {...q, public: rows, sibling: rows, phase: "exported"}}
  }
  action Retire = all {q.phase != "new", not(q.retired), q' = {...q, retired: true,
    blocks: if (Mutation == "alias") List((List(99),List(99))) else q.blocks}}
  action Read = {
    nondet axis = Set(0,1).oneOf()
    val used = if (Mutation == "axis") 0 else axis
    all {q.phase != "new", not(q.ready.contains(axis)), q' = {...q,
      ready: q.ready.union(Set(axis)), reads: q.reads.set(axis,SelectedCollect(q.blocks,used,0))}}
  }
  action Mutate = all {q.phase == "exported", not(q.mutated), q' = {...q,
    mutated: true, public: List((99,99)), sibling: if (Mutation == "shared") List((99,99)) else q.sibling}}
  action step = any {Capture, Export, Retire, Read, Mutate}
  val SharedPlanExact = SelfAxes(q.blocks) implies SharedLeft(q.blocks,0) == Select(q.held,0,0)
  val FrozenExact = q.phase != "new" implies ProductRows(q.blocks) == q.held
  val OrderedExact = q.phase == "exported" and not(q.mutated) implies q.public == q.held
  val IndependentReads = q.phase == "exported" implies q.sibling == q.held
  val CountExact = q.phase != "new" implies q.count == q.held.length()
  val AxisExact = q.ready.forall(a => q.reads.get(a) == Select(q.held,a,0))
}
