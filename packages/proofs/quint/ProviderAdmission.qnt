// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ProviderAdmission {
  const Rows: Set[int]
  const Keys: Set[int]
  const Total: List[int]
  const Delta: List[int]
  const KeyOf: int -> int
  const Mutation: str
  pure val TotalRows = List(0,0,1,2)
  pure val DeltaRows = List(0)
  pure val RowKey = Rows.mapBy(r => if (r < 2) 0 else 1)
  pure val Zero = Rows.mapBy(_ => 0)
  pure def Occurrences(rows: List[int]): int -> int = Rows.mapBy(r => rows.indices().filter(i => rows.nth(i) == r).size())
  pure def Source(which: str): int -> int = Occurrences(if (which == "all") Total else Delta)
  pure def Mass(packet: int -> int, rows: Set[int]): int = rows.fold(0,(acc,r) => acc+packet.get(r))
  pure def Bucket(k: int): Set[int] = Rows.filter(r => KeyOf.get(r) == k)
  pure def Cap(packet: int -> int, witness: int -> int): bool = Rows.forall(r => packet.get(r) <= witness.get(r))
  pure def Matching(packet: int -> int, witness: int -> int, k: int): bool = Mass(packet,Bucket(k)) == Mass(witness,Bucket(k))
  pure def SetMatching(packet: int -> int, witness: int -> int, k: int): bool = Bucket(k).forall(r => (packet.get(r)>0) == (witness.get(r)>0))
  pure def Admissible(packet: int -> int, witness: int -> int, k: int): bool = Cap(packet,witness) and Matching(packet,witness,k)
  pure def Selected(packet: int -> int, k: int): int -> int = Rows.mapBy(r => if (KeyOf.get(r) == k) packet.get(r) else 0)
  pure val Packets = Rows.setOfMaps(0.to(Total.length()+1))
  type State = {lane: str, wanted: int, packet: int -> int, approved: int -> int, result: int -> int, phase: str,
    cacheLive: bool, callbacks: int, mutated: bool, retried: bool}
  var q: State
  action init = q' = {lane: "all", wanted: Keys.chooseSome(), packet: Zero, approved: Zero, result: Zero, phase: "idle", cacheLive: true, callbacks: 0, mutated: false, retried: false}
  action Submit(which: str, k: int, packet: int -> int): bool = all {q.phase == "idle", q' = {...q, lane: which, wanted: k, packet: packet, phase: "returned"}}
  action Check = {
    val witness = Source(if (Mutation == "allwitness") "all" else q.lane)
    val ok = if (Mutation == "nocap") Matching(q.packet,witness,q.wanted)
      else if (Mutation == "set") Cap(q.packet,witness) and SetMatching(q.packet,witness,q.wanted) else Admissible(q.packet,witness,q.wanted)
    all {q.phase == "returned", q' = {...q, phase: if (ok) "admitted" else "failed", approved: if (ok) q.packet else Zero,
      cacheLive: if (ok) q.cacheLive else Mutation == "retain", callbacks: if (Mutation == "early" and not(ok)) 1 else 0}}
  }
  action MutateBuffer = all {q.phase == "admitted", not(q.mutated), q' = {...q, packet: Zero, mutated: true}}
  action Consume = all {q.phase == "admitted", q' = {...q, phase: "done", callbacks: 1, result: Selected(if (Mutation == "borrow") q.packet else q.approved,q.wanted)}}
  action Retry = all {q.phase == "failed", not(q.retried), q' = {...q, phase: "idle", cacheLive: true, callbacks: 0, retried: true, packet: Zero, approved: Zero, result: Zero, mutated: false}}
  action submitStep = {nondet which = Set("all","delta").oneOf(); nondet k = Keys.oneOf(); nondet packet = Packets.oneOf(); Submit(which,k,packet)}
  action step = any {Check, MutateBuffer, Consume, Retry, submitStep}
  val CountCaps = Set("admitted","done").contains(q.phase) implies Cap(q.approved,Source(q.lane))
  val MatchingExact = Set("admitted","done").contains(q.phase) implies Bucket(q.wanted).forall(r => q.approved.get(r) == Source(q.lane).get(r))
  val OutputExact = q.phase == "done" implies q.result == Selected(Source(q.lane),q.wanted)
  val DetachedPacket = q.phase == "done" implies q.result == Selected(q.approved,q.wanted)
  val NoEarlyCallbacks = Set("idle","returned","failed").contains(q.phase) implies q.callbacks == 0
  val FailedCacheRevoked = q.phase == "failed" implies not(q.cacheLive)

}

module ProviderAdmissionFixture {
  const Fault: str
  import ProviderAdmission(Rows = Set(0,1,2,3), Keys = Set(0,1),
    Total = List(0,0,1,2), Delta = List(0), KeyOf = Map(0 -> 0,1 -> 0,2 -> 1,3 -> 1), Mutation = Fault).*
}
