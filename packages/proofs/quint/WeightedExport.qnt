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
  // Frozen owner IDs model bucket identity, never global value equality.
  pure def Owners(bs: List[Block], axis: int, key: int): Set[int] =
    bs.foldl((0,Set()), (acc,b) => (acc._1 + 1,
      if (Has(if (axis == 0) b._1 else b._2,key)) acc._2.union(Set(acc._1)) else acc._2))._2
  pure def IndexedMember(bs: List[Block], p: Row): bool = {
    val left = Owners(bs,0,p._1)
    val right = Owners(bs,1,p._2)
    if (Mutation == "owner-cross") left.size() > 0 and right.size() > 0
    else if (Mutation == "member-miss") false
    else left.intersect(right).size() > 0
  }
  // Composite bindings are private to one invocation. Empty binding lists
  // represent unconstrained slots; #f-like endpoint values are ordinary keys.
  type Condition = (int,int)
  type GroupRow = (int,int,int)
  pure def GroupRows(bs: List[Block]): List[GroupRow] =
    bs.foldl((0,List()), (acc,b) => (acc._1 + 1, acc._2.concat(
      Product(b).foldl(List(), (rows,p) => rows.append((acc._1,p._1,p._2))))))._2
  pure def Bindings(cs: List[Condition], column: int): List[int] =
    cs.foldl(List(), (acc,c) => if (c._1 == column) acc.append(c._2) else acc)
  pure def Bound(values: List[int], value: int): bool =
    if (Mutation == "repeat-conflict" and values.length() > 0) values.nth(0) == value
    else values.foldl(true, (ok,key) => ok and key == value)
  pure def GroupQuery(bs: List[Block], cs: List[Condition]): List[GroupRow] = {
    val group = Bindings(cs,0)
    val left = Bindings(cs,1)
    val right = Bindings(cs,2)
    bs.foldl((0,List()), (acc,b) => {
      val axisLeft = if (Mutation == "group-owner") bs.foldl(List(), (xs,owner) => xs.concat(owner._1)) else b._1
      val axisRight = if (Mutation == "group-owner") bs.foldl(List(), (xs,owner) => xs.concat(owner._2)) else b._2
      val selectedLeft = axisLeft.foldl(List(), (xs,x) => if (Bound(left,x)) xs.append(x) else xs)
      val selectedRight = axisRight.foldl(List(), (ys,y) => if (Bound(right,y)) ys.append(y) else ys)
      (acc._1 + 1, if (Bound(group,acc._1)) acc._2.concat(
        Product((selectedLeft,selectedRight)).foldl(List(), (rows,p) => rows.append((acc._1,p._1,p._2)))) else acc._2)
    })._2
  }
  pure def GroupSelect(rows: List[GroupRow], cs: List[Condition]): List[GroupRow] =
    rows.foldl(List(), (acc,p) => if (cs.foldl(true, (ok,c) => ok and
      (if (c._1 == 0) p._1 else if (c._1 == 1) p._2 else p._3) == c._2)) acc.append(p) else acc)
  // Frozen sorted plans are constructed once. Each query only moves private
  // cursors; at most left.length + right.length merge steps are required.
  pure def OwnerPlan(bs: List[Block], axis: int, key: int): List[int] =
    bs.foldl((0,List()), (acc,b) => (acc._1 + 1,
      if (Has(if (axis == 0) b._1 else b._2,key)) acc._2.append(acc._1) else acc._2))._2
  pure def MergePlans(left: List[int], right: List[int]): List[int] = {
    val merged = left.concat(right).foldl((left,right,List()), (cursor,_unused) => {
      val a = cursor._1
      val b = cursor._2
      val rows = cursor._3
      if (a.length() == 0 or b.length() == 0) cursor
      else if (a.nth(0) < b.nth(0)) (a.slice(1,a.length()),
        if (Mutation == "merge-skip") b.slice(1,b.length()) else b, rows)
      else if (b.nth(0) < a.nth(0)) (a,b.slice(1,b.length()),rows)
      else (a.slice(1,a.length()),b.slice(1,b.length()),rows.append(a.nth(0)))
    })._3
    if (Mutation == "merge-order") Reverse(merged) else merged
  }
  val FrozenPlanExact = q.phase != "new" implies Set(0,1,2,99).forall(x =>
    Set(0,1,2,99).forall(y => {
      val left = OwnerPlan(q.blocks,0,x)
      val right = OwnerPlan(q.blocks,1,y)
      MergePlans(left,right) == left.foldl(List(), (acc,id) =>
        if (Has(right,id)) acc.append(id) else acc)
    }))
  pure def PointQuery(bs: List[Block], group: int, left: int, right: int): List[GroupRow] =
    bs.foldl((0,List()), (acc,b) => (acc._1 + 1,
      if ((Mutation == "point-prefix" or acc._1 == group) and
          (if (Mutation == "point-owner")
            Owners(bs,0,left).size() > 0 and Owners(bs,1,right).size() > 0
           else Has(b._1,left) and Has(b._2,right)))
      acc._2.append((acc._1,left,right)) else acc._2))._2
  // Constructor-local identity associations for a bounded tiny cut.
  pure def TinyOwner(bs: List[Block], owner: int): List[Block] =
    bs.foldl((0,List()), (acc,b) => (acc._1 + 1,
      if (acc._1 == (if (Mutation == "tiny-owner") 0 else owner)) acc._2.append(b) else acc._2))._2
  val TinyOwnerExact = q.phase != "new" and q.blocks.length() <= 2 implies
    Set(0,1,99).forall(owner => TinyOwner(q.blocks,owner) ==
      (if (owner < q.blocks.length()) List(q.blocks.nth(owner)) else List()))
  // Prefix narrowing precedes scalar endpoint publication, retaining order.
  pure def RoutedPoint(bs: List[Block], group: int, left: int, right: int): List[GroupRow] =
    PointQuery(bs,group,left,right).foldl(List(), (rows,p) =>
      if (Mutation == "point-drop" and p._1 == 1) rows else rows.append(p))
  val RoutedPointExact = q.phase != "new" implies Set(0,1,99).forall(g =>
    Set(0,1,2,99).forall(x => Set(0,1,2,99).forall(y =>
      RoutedPoint(q.blocks,g,x,y) == GroupSelect(GroupRows(q.blocks),List((0,g),(1,x),(2,y))))))
  pure def PointMember(axis: List[int], key: int): bool =
    Has(axis.slice(0, if (axis.length() < 4) axis.length() else 4),key) or
      (Mutation != "point-head-drop" and Has(axis,key))
  val PointMemberExact = q.phase != "new" implies Set(List(),List(0,1,2,3,4,5),List(5,4,3,2,1,0)).forall(axis =>
    Set(0,1,2,3,4,5,99).forall(key => PointMember(axis,key) == Has(axis,key)))
  val CompleteKeyExact = q.phase != "new" implies Set(0,1,99).forall(g =>
    Set(0,1,2,99).forall(x => Set(0,1,2,99).forall(y =>
      PointQuery(q.blocks,g,x,y) == GroupSelect(GroupRows(q.blocks),List((0,g),(1,x),(2,y))))))
  val GroupedQueryExact = q.phase != "new" implies
    Set(List(),List((0,0),(1,0),(2,1)),List((2,1),(0,0),(1,0),(0,0)),
      List((1,0),(2,1)),List((1,0),(1,0)),List((1,0),(1,1)),
      List((0,99),(2,0))).forall(cs => GroupQuery(q.blocks,cs) == GroupSelect(GroupRows(q.blocks),cs))
  // Only the first stored value is retained. Every repeat still constrains
  // admission, and range validation precedes conflict rejection.
  pure def FirstSlot(slot: List[int], value: int): List[int] =
    if (slot.length() == 0) List(value) else slot
  type CompactSlots = {group: List[int], left: List[int], right: List[int], conflict: bool}
  pure def Compact(cs: List[Condition]): CompactSlots = cs.foldl(
    {group: List(), left: List(), right: List(), conflict: false}, (acc,c) => {
      val slot = if (c._1 == 0) acc.group else if (c._1 == 1) acc.left else acc.right
      val conflict = acc.conflict or (slot.length() > 0 and slot.nth(0) != c._2)
      {...acc,
        group: if (c._1 == 0) FirstSlot(acc.group,c._2) else acc.group,
        left: if (c._1 == 1) FirstSlot(acc.left,c._2) else acc.left,
        right: if (c._1 == 2) FirstSlot(acc.right,c._2) else acc.right,
        conflict: Mutation != "compact-conflict" and conflict}
    })
  pure def CompactValid(cs: List[Condition]): bool =
    (Mutation == "compact-range" and Compact(cs).conflict) or
      cs.foldl(true, (valid,c) => valid and c._1 >= 0 and c._1 < 3)
  pure def CompactQuery(bs: List[Block], cs: List[Condition]): List[GroupRow] = {
    val slots = Compact(cs)
    if (not(CompactValid(cs)) or slots.conflict) List()
    else GroupRows(bs).foldl(List(), (rows,p) => if (Bound(slots.group,p._1) and
      Bound(slots.left,p._2) and Bound(slots.right,p._3)) rows.append(p) else rows)
  }
  val CompactQueryExact = q.phase != "new" implies
    Set(List((2,1),(0,0),(1,0),(0,0),(2,1)),
      List((1,0),(2,1),(1,0),(2,1)),List((1,0),(2,1),(1,1)),
      List((0,0),(1,0)),List((0,99),(1,0),(2,1))).forall(cs =>
        CompactQuery(q.blocks,cs) == GroupSelect(GroupRows(q.blocks),cs))
  // Index absence is separate from endpoint absence: publication must still
  // use the exact frozen owner fallback when a multi-owner plan is omitted.
  pure def CompactWithPlan(bs: List[Block], cs: List[Condition], ready: bool): List[GroupRow] =
    if (ready) CompactQuery(bs,cs)
    else if (Mutation == "compact-plan-miss") List() else GroupSelect(GroupRows(bs),cs)
  val CompactFallbackExact = q.phase != "new" implies
    Set(true,false).forall(ready => Set(List((1,0),(2,1)),List((1,2),(2,0)),
      List((2,1),(1,0),(2,1))).forall(cs =>
        CompactWithPlan(q.blocks,cs,ready) == GroupSelect(GroupRows(q.blocks),cs)))
  // Costs can select any covered coordinate route. Exact filtering and order
  // remain independent of which frozen bucket/plan was cheapest.
  pure def AtCoordinate(cs: List[Condition], column: int): List[Condition] =
    cs.foldl(List(), (selected,c) => if (c._1 == column) selected.append(c) else selected)
  pure def Narrow(a: (List[GroupRow],int), b: (List[GroupRow],int)): (List[GroupRow],int) =
    if (b._2 < a._2) b else a
  pure def NarrowQuery(bs: List[Block], cs: List[Condition], costs: (int,int,int)): List[GroupRow] = {
    val rows = GroupRows(bs)
    val group = (GroupSelect(rows,AtCoordinate(cs,0)),costs._1)
    val left = (GroupSelect(rows,AtCoordinate(cs,1)),costs._2)
    val right = (GroupSelect(rows,AtCoordinate(cs,2)),costs._3)
    val candidate = Narrow(Narrow(group,left),right)
    GroupSelect(if (Mutation == "compact-candidate") List() else candidate._1,cs)
  }
  val CompactNarrowExact = q.phase != "new" implies
    Set((32,1,2),(1,32,2),(32,2,1),(2,2,2)).forall(costs =>
      Set(List((0,0),(1,0),(2,0)),List((0,1),(1,2)),List((0,0),(2,0))).forall(cs =>
        NarrowQuery(q.blocks,cs,costs) == GroupSelect(GroupRows(q.blocks),cs)))
  val CompactRangeExact = q.phase != "new" implies
    not(CompactValid(List((1,0),(1,1),(3,0))))
  // One paired cursor owns admission and first-value slots. No publication
  // occurs before the entire suffix has met syntax and range obligations.
  type Admission = {slots: int -> List[int], rank: int, steps: int}
  pure def Stream(cs: List[Condition]): Admission = cs.foldl(
    {slots: Map(0 -> List(),1 -> List(),2 -> List()), rank: 0, steps: 0}, (acc,c) => {
      val syntax = c._1 >= 0
      val valid = syntax and c._1 < 3
      val previous = if (valid) acc.slots.get(c._1) else List()
      val conflict = previous.length() > 0 and previous.nth(0) != c._2
      val rank = if (not(syntax)) 3 else if (not(valid)) 2 else if (conflict) 1 else 0
      if (Mutation == "admit-early" and acc.rank > 0) acc else {
        slots: if (valid) acc.slots.set(c._1,
          if (Mutation == "admit-last") List(c._2) else FirstSlot(previous,c._2)) else acc.slots,
        rank: if (Mutation == "admit-priority" and acc.rank > 0) acc.rank else if (rank > acc.rank) rank else acc.rank,
        steps: acc.steps + 1}
    })
  pure def AdmissionQueries: Set[List[Condition]] = Set(
    List(),List((0,0),(1,0),(2,1)),List((2,1),(0,0),(1,0),(2,1)),
    List((1,0),(1,1)),List((1,0),(1,1),(3,0)),List((3,0),(1,0),(-1,0)),
    List((1,0),(1,1),(-1,0)),List((0,99),(2,0)),List((1,0),(1,0)))
  pure def ExpectedRank(cs: List[Condition]): int =
    if (cs.foldl(false,(bad,c) => bad or c._1 < 0)) 3
    else if (cs.foldl(false,(bad,c) => bad or c._1 >= 3)) 2
    else if (Compact(cs).conflict) 1 else 0
  val StreamAdmissionExact = q.phase != "new" implies AdmissionQueries.forall(cs => Stream(cs).rank == ExpectedRank(cs))
  val StreamAdmissionComplete = q.phase != "new" implies AdmissionQueries.forall(cs => Stream(cs).steps == cs.length())
  val StreamFirstSlots = q.phase != "new" implies AdmissionQueries.forall(cs => Set(0,1,2).forall(c =>
    Stream(cs).slots.get(c) == cs.foldl(List(),(slot,x) =>
      if (x._1 == c) FirstSlot(slot,x._2) else slot)))
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
  val MembershipExact = q.phase != "new" implies Set(0,1,2,99).forall(x =>
    Set(0,1,2,99).forall(y => IndexedMember(q.blocks,(x,y)) == q.held.foldl(false, (found,p) => found or p == (x,y))))
  val DifferenceExact = q.phase != "new" implies {
    val older = SelectedBlocks(q.blocks,0,0)
    q.held.foldl(List(), (rows,p) => if (IndexedMember(older,p)) rows else rows.append(p)) ==
      q.held.foldl(List(), (rows,p) => if (ProductRows(older).foldl(false, (found,row) => found or row == p)) rows else rows.append(p))
  }
  val SharedPlanExact = SelfAxes(q.blocks) implies SharedLeft(q.blocks,0) == Select(q.held,0,0)
  val FrozenExact = q.phase != "new" implies ProductRows(q.blocks) == q.held
  val OrderedExact = q.phase == "exported" and not(q.mutated) implies q.public == q.held
  val IndependentReads = q.phase == "exported" implies q.sibling == q.held
  val CountExact = q.phase != "new" implies q.count == q.held.length()
  val AxisExact = q.ready.forall(a => q.reads.get(a) == Select(q.held,a,0))
}
