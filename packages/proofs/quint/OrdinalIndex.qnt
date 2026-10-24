// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite representation checks; Vec/HashMap and allocator source refinement
// remain separate obligations. Codes are query-owned, injective value ordinals.
module OrdinalIndex {
  const Mutation: str
  const NativeLimit: int
  val Keys = Set(0,1,2,3,4,5,6,7,8,9,10,11,12,16,1024)
  val Inputs = List(16,16,0,1,2,3,4,5,6,7,8,9,10,11,12,16,0,1024,16)
  type State = {extent: int, dense: int -> List[int], sparse: int -> List[int],
                truth: int -> List[int], seen: Set[int], cursor: int}
  var q: State
  pure def Target(key: int): int = if (key < 1) 1 else if (key < 2) 2
    else if (key < 4) 4 else if (key < 8) 8 else if (key < 16) 16
    else if (key < 32) 32 else 2048
  pure def Fits(target: int, bound: int, nativeLimit: int): bool =
    (target <= bound or Mutation == "unbounded-spine") and
    (target <= nativeLimit or Mutation == "ignore-byte-limit")
  action init = q' = {extent: 0, dense: Keys.mapBy(_ => List()),
    sparse: Keys.mapBy(_ => List()), truth: Keys.mapBy(_ => List()), seen: Set(), cursor: 0}
  action step = {
    val key = Inputs.nth(q.cursor)
    val target = Target(key)
    val grow = key >= q.extent and Fits(target, (q.seen.size()+1)*2+4, NativeLimit)
    val extent = if (grow) target else q.extent
    val dense = Keys.mapBy(k => if (grow and k >= q.extent and k < extent)
      (if (Mutation == "drop-moved") List() else if (Mutation == "reverse-moved")
        q.sparse.get(k).foldl(List(), (xs,x) => List(x).concat(xs)) else q.sparse.get(k))
      else q.dense.get(k))
    val sparse = Keys.mapBy(k => if (k < extent and Mutation != "retain-moved") List() else q.sparse.get(k))
    val row = List(q.cursor)
    all {q.cursor < Inputs.length(), q' = {
      extent: extent, seen: q.seen.union(Set(key)), cursor: q.cursor+1,
      dense: if (key < extent) dense.set(key, dense.get(key).concat(row)) else dense,
      sparse: if (key >= extent and Mutation != "skip-sparse") sparse.set(key, sparse.get(key).concat(row)) else sparse,
      truth: q.truth.set(key, q.truth.get(key).concat(row))
    }}
  }
  val ExactRows = Keys.forall(k =>
    (if (k < q.extent) q.dense.get(k) else q.sparse.get(k)) == q.truth.get(k))
  val ExclusiveBins = Keys.forall(k => k < q.extent implies q.sparse.get(k) == List())
  val SpineBound = q.extent <= 2*q.seen.size()+6
  val NativeBound = q.extent <= NativeLimit
  val GuardExact = q.cursor == 0 or Set(1,4,8,32,2048).forall(target => Set(0,6,16,4096).forall(bound =>
    Set(4,16,4096).forall(limit => Fits(target,bound,limit) == (target <= bound and target <= limit))))
  val SameRequestCost = q.cursor == 0 or {
    // Two requests have different expensive phases. Componentwise maxima do
    // not constitute the cost partition of the longest request.
    val total = 10
    val replace = 8
    val exported = if (Mutation == "mix-phase-maxima") 7 else 1
    val validation = if (Mutation == "drop-validation") 0 else 1
    total == replace + exported + validation
  }
}
