// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Encoding preserves an existing receipt; this model grants no admission.
module SourceRowTransfer {
  const Mutation: str
  // BEGIN GENERATED SOURCE ROW PACKET
  pure def source_row_packet(requested: bool, actor: bool, ready: bool): bool =
    ready or (requested and not(actor))
  // END GENERATED SOURCE ROW PACKET
  type State = {phase: int, requested: bool, actor: bool, complete: bool,
    supported: bool, cancelled: bool, exhausted: bool, provenance: int,
    generation: int, packed: bool, rows: List[int], expected: List[int],
    completeOut: bool, cancelledOut: bool, exhaustedOut: bool,
    provenanceOut: int, generationOut: int}
  var q: State
  action init = {
    nondet requested = Set(false,true).oneOf()
    nondet actor = Set(false,true).oneOf()
    nondet complete = Set(false,true).oneOf()
    nondet supported = Set(false,true).oneOf()
    nondet cancelled = Set(false,true).oneOf()
    nondet exhausted = Set(false,true).oneOf()
    q' = {phase: 0, requested: requested, actor: actor, complete: complete,
      supported: supported, cancelled: cancelled, exhausted: exhausted,
      provenance: 7, generation: 3, packed: false, rows: List(),
      expected: List(-1,0,-1,2), completeOut: false, cancelledOut: false,
      exhaustedOut: false, provenanceOut: 0, generationOut: 0}
  }
  action encode = {
    val ready = q.requested and q.actor and q.complete
    val selected = if (Mutation == "actor-only") ready
      else if (Mutation == "missing-optin") true
      else source_row_packet(q.requested,q.actor,ready)
    all {q.phase == 0,
      q' = {...q, phase: 1,
        packed: selected and (q.supported or Mutation == "unsupported-packet"),
        rows: if (Mutation == "reverse-rows") List(2,-1,0,-1) else q.expected,
        completeOut: if (Mutation == "force-complete") true else q.complete,
        cancelledOut: if (Mutation == "clear-cancel") false else q.cancelled,
        exhaustedOut: if (Mutation == "clear-resource") false else q.exhausted,
        provenanceOut: if (Mutation == "forge-provenance") 8 else q.provenance,
        generationOut: if (Mutation == "stale-generation") 0 else q.generation}
    }
  }
  action step = encode
  val SelectionExact = q.phase == 0 or
    q.packed == (q.requested and (not(q.actor) or q.complete) and q.supported)
  val TransportOptIn = q.phase == 0 or not(q.packed) or q.requested
  val Representable = q.phase == 0 or not(q.packed) or q.supported
  val RowsPreserved = q.phase == 0 or q.rows == q.expected
  val CompletionPreserved = q.phase == 0 or q.completeOut == q.complete
  val CancellationPreserved = q.phase == 0 or q.cancelledOut == q.cancelled
  val ResourcePreserved = q.phase == 0 or q.exhaustedOut == q.exhausted
  val ProvenancePreserved = q.phase == 0 or q.provenanceOut == q.provenance
  val GenerationPreserved = q.phase == 0 or q.generationOut == q.generation
}
