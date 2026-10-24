// Guarded scalar aggregate classification. Native MOP compatibility is a premise;
// count public classifier calls, not inferred heap allocation or wall time.
module AggregateAdmission {
  const Mutation: str
  type Observation = {accepted: bool, trace: List[int], probes: int}
  var ready: bool
  action init = ready' = false
  action step = ready' = true
  pure def Old(owned: bool, children: bool, revision: bool, bad: int, hook: int): Observation = {
    accepted: bad == 0 and hook == 0,
    trace: if (hook > 0) List(hook) else if (not(owned)) List(7)
      else if (not(children)) List(8) else if (not(revision)) List(9) else List(),
    probes: if (hook > 0) hook else 6
  }
  pure def New(owned: bool, children: bool, revision: bool, symbol: bool, bad: int, hook: int): Observation = {
    val issued = owned or Mutation == "forge-shape"
    val terms = children or Mutation == "ignore-children"
    val current = revision or Mutation == "ignore-revision"
    val protocol = hook == 0 or Mutation == "ignore-protocol"
    val checked = bad == 0 or Mutation == "skip-fields" or Mutation == "reuse-prior"
    val fast = issued and terms and current and symbol and protocol and checked
    val old = Old(owned,children,revision,bad,hook)
    if (Mutation == "reject-tuple" and not(symbol)) {accepted: false, trace: old.trace, probes: old.probes}
    else if (fast) {accepted: true, trace: List(), probes: if (Mutation == "keep-public-probes") 6 else 0}
    else old
  }
  pure def Cases(role: str): bool = Set(false,true).forall(owned => Set(false,true).forall(children =>
    Set(false,true).forall(revision => Set(false,true).forall(symbol =>
    Set(0,1,2,3,4,5,6,7,8,9).forall(bad => Set(0,1,2,3,4,5,6).forall(hook => {
      val actual = New(owned,children,revision,symbol,bad,hook)
      val old = Old(owned,children,revision,bad,hook)
      val fast = owned and children and revision and symbol and bad == 0 and hook == 0
      if (role == "admission") actual.accepted == old.accepted
      else if (role == "callbacks") actual.trace == old.trace
      else if (fast) actual.probes == 0 else actual.probes == old.probes
    }))))))
  val AdmissionExact = not(ready) or Cases("admission")
  val CallbackExact = not(ready) or Cases("callbacks")
  val PublicProbeCost = not(ready) or Cases("probes")
  // A signed SDK report is evidence only for its declared, complete, normal-return
  // nonoverlapping scope. No raw/net stack counter is promoted to a total.
  pure def Allocation(bound: bool, complete: bool, sameStack: bool, outer: bool, precise: bool, bytes: int, start: int, end: int): bool =
    (bound or Mutation == "promote-foreign-allocation") and complete and
    (sameStack or Mutation == "promote-net-stack") and outer and
    (precise or Mutation == "ignore-counter-precision") and
    (bytes >= 0 or Mutation == "promote-negative-allocation") and
    (start >= 0 or Mutation == "ignore-negative-raw") and
    end >= start and
    (bytes <= end-start or Mutation == "exceed-raw-bound")
  val AllocationScope = not(ready) or Set(false,true).forall(bound => Set(false,true).forall(complete =>
    Set(false,true).forall(stack => Set(false,true).forall(outer => Set(false,true).forall(precise => Set(-1,0,1,2).forall(bytes =>
    Set(-1,0,1).forall(start => Set(0,1,2).forall(end =>
      Allocation(bound,complete,stack,outer,precise,bytes,start,end) ==
      (bound and complete and stack and outer and precise and bytes >= 0 and start >= 0 and end >= start and bytes <= end-start)))))))))
}
