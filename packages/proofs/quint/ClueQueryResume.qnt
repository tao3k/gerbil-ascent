// Finite query/state abstraction, not a host resource or exploration limit.
module ClueQueryResume {
  const Mutation: str
  type State = {phase: int, query: int, saved: int, caller: int,
    facts: Set[int], original: Set[int], visible: Set[int],
    active: bool, authority: bool, history: Set[int],
    contract: int, savedContract: int, readSeen: Set[int], originalSeen: Set[int]}
  var q: State
  pure def answers(query: int, facts: Set[int]): Set[int] =
    facts.filter(i => if (query == 0) Set(0, 1, 4).contains(i)
      else if (query == 1) Set(2, 3).contains(i) else false)
  action init = q' = {phase: 0, query: -1, saved: -1, caller: -1,
    facts: Set(0, 1, 2, 3), original: Set(), visible: Set(),
    active: false, authority: false, history: Set(0, 1),
    contract: 0, savedContract: 0, readSeen: Set(), originalSeen: Set()}
  action Declare = {
    nondet query = Set(0, 1).oneOf()
    all {q.phase == 0,
      q' = {...q, phase: 1, query: query, saved: query,
        original: answers(query, q.facts), visible: answers(query, q.facts), active: true,
        readSeen: answers(query, q.facts), originalSeen: answers(query, q.facts)}}
  }
  action Interrupt = all {q.phase == 1,
    q' = {...q, phase: 2, query: -1, active: false, visible: Set()}}
  action ChangeFacts = all {q.phase == 2, not(q.facts.contains(4)),
    q' = {...q, facts: q.facts.union(Set(4))}}
  action WithdrawFact = all {q.phase == 2, q.facts.contains(0),
    q' = {...q, facts: q.facts.exclude(Set(0))}}
  action ChangeContract = all {q.phase == 2, q.contract == 0,
    q' = {...q, contract: 1}}
  action LoseDeclaration = all {q.phase == 2, q.saved >= 0,
    q' = {...q, saved: -1}}
  action Resume = all {q.phase == 2,
    val usable = q.saved >= 0 or Mutation == "guess-missing"
    val query = if (Mutation == "drop-query") 2 else if (q.saved >= 0) q.saved else 0
    q' = {...q, phase: 3, query: if (usable) query else -1, active: usable,
      visible: if (not(usable)) Set() else if (Mutation == "freeze-results") q.original
        else answers(query, q.facts),
      authority: Mutation == "authorize-resume",
      readSeen: if (Mutation == "replay-all") Set()
        else if (q.contract != q.savedContract and Mutation != "reuse-changed-contract") Set()
        else if (Mutation == "keep-removed-read") q.originalSeen
        else q.originalSeen.intersect(q.facts),
      history: if (Mutation == "erase-history") Set() else q.history}}
  action Override = {
    nondet caller = Set(0, 1, 2, 3).oneOf()
    all {q.phase == 3,
      val query = if (Mutation == "pin-caller") q.saved else caller
      q' = {...q, phase: 4, caller: caller, query: query, active: true,
        visible: answers(query, q.facts)}}
  }
  action step = any {Declare, Interrupt, ChangeFacts, WithdrawFact, ChangeContract, LoseDeclaration, Resume, Override}
  val Restored = not(q.phase == 3 and q.saved >= 0) or q.query == q.saved
  val CurrentFacts = not(q.active) or q.visible == answers(q.query, q.facts)
  val MissingIsUnknown = not(q.phase == 3 and q.saved < 0) or not(q.active)
  val CallerOwnsScope = q.phase != 4 or q.query == q.caller
  val NoAuthority = not(q.authority)
  val History = q.history == Set(0, 1)
  val ExactReads = q.phase < 3 or q.readSeen ==
    (if (q.contract == q.savedContract) q.originalSeen.intersect(q.facts) else Set())
  val Safety = Restored and CurrentFacts and MissingIsUnknown and CallerOwnsScope and NoAuthority and History and ExactReads
}
