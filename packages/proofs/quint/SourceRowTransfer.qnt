// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Encoding preserves an existing receipt; this model grants no admission.
module SourceRowTransfer {
  const Mutation: str
  // BEGIN GENERATED SOURCE ROW PACKET
  pure def source_row_packet(requested: bool, actor: bool, ready: bool): bool =
    ready or (requested and not(actor))
  // END GENERATED SOURCE ROW PACKET
  // BEGIN GENERATED PROJECTION ROW SHAPES
  pure def projection_row_packet(requested: bool, supported: bool): bool =
    requested and supported
  pure def projection_element(shape: int, index: int): int =
    if (shape == 1 and index == 1) 2 else
    if (shape == 6) 7 else
    0
  pure def projection_field(shape: int, key: str): int =
    if (shape == 2 and key == "relations") 3 else
    if (shape == 2 and key == "program") 5 else
    if (shape == 3) 4 else
    if (shape == 5 and key == "relations") 6 else
    if (shape == 7 and key == "rows") 4 else
    0
  // END GENERATED PROJECTION ROW SHAPES
  pure def checked_field(shape: int, key: str): int =
    if (Mutation == "missing-projection-route" and shape == 2 and key == "program") 0
    else if (Mutation == "packet-in-arbitrary-value" and shape == 0 and key == "rows") 4
    else if (Mutation == "metadata-row-alias" and shape == 7 and key == "columns") 4
    else projection_field(shape, key)
  type Metadata = {occurrences: bool, columns: List[int], rules: List[int],
    queries: List[int], values: List[int]}
  type State = {phase: int, requested: bool, actor: bool, complete: bool,
    supported: bool, cancelled: bool, exhausted: bool, provenance: int,
    generation: int, packed: bool, rows: List[int], expected: List[int],
    completeOut: bool, cancelledOut: bool, exhaustedOut: bool,
    provenanceOut: int, generationOut: int, metadata: Metadata, metadataOut: Metadata,
    projectionPacked: bool}
  var q: State
  action init = {
    nondet requested = Set(false,true).oneOf()
    nondet actor = Set(false,true).oneOf()
    nondet complete = Set(false,true).oneOf()
    nondet supported = Set(false,true).oneOf()
    nondet cancelled = Set(false,true).oneOf()
    nondet exhausted = Set(false,true).oneOf()
    val metadata = {occurrences: true, columns: List(1,2), rules: List(3,1),
      queries: List(9,7), values: List(0,1,0)}
    q' = {phase: 0, requested: requested, actor: actor, complete: complete,
      supported: supported, cancelled: cancelled, exhausted: exhausted,
      provenance: 7, generation: 3, packed: false, rows: List(),
      expected: List(-1,0,-1,2), completeOut: false, cancelledOut: false,
      exhaustedOut: false, provenanceOut: 0, generationOut: 0,
      metadata: metadata, metadataOut: metadata, projectionPacked: false}
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
        generationOut: if (Mutation == "stale-generation") 0 else q.generation,
        projectionPacked: if (Mutation == "couple-projection-completion")
          selected and q.supported
          else projection_row_packet(q.requested or Mutation == "skip-projection-optin",
            q.supported or Mutation == "unsupported-projection-packet"),
        metadataOut: {...q.metadata,
          occurrences: if (Mutation == "erase-occurrences") false else q.metadata.occurrences,
          columns: if (Mutation == "change-columns") List(2,1) else q.metadata.columns,
          rules: if (Mutation == "change-rules") List() else q.metadata.rules,
          queries: if (Mutation == "change-queries") List(7,9) else q.metadata.queries,
          values: if (Mutation == "change-pool") List() else q.metadata.values}}
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
  val OccurrencesPreserved = q.phase == 0 or q.metadataOut.occurrences == q.metadata.occurrences
  val ColumnsPreserved = q.phase == 0 or q.metadataOut.columns == q.metadata.columns
  val RulesPreserved = q.phase == 0 or q.metadataOut.rules == q.metadata.rules
  val QueriesPreserved = q.phase == 0 or q.metadataOut.queries == q.metadata.queries
  val PoolPreserved = q.phase == 0 or q.metadataOut.values == q.metadata.values
  val ProjectionSelectionExact = q.phase == 0 or q.projectionPacked == (q.requested and q.supported)
  val ProjectionTransportOptIn = q.phase == 0 or not(q.projectionPacked) or q.requested
  val ProjectionRepresentable = q.phase == 0 or not(q.projectionPacked) or q.supported
  val ProjectionPath = q.phase == 0 or checked_field(projection_element(checked_field(checked_field(projection_element(1,1),
    "program"),"relations"),0),"rows") == 4
  val OrdinaryValuesOpaque = q.phase == 0 or Set("rows","program","relations").forall(key => checked_field(0,key) == 0)
  val RelationMetadataOpaque = q.phase == 0 or (checked_field(7,"columns") == 0 and checked_field(5,"queries") == 0)
}
