-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import WeightedExportCapacity

/-! A representation change after catalogue capture. Metadata includes the
source generation, rules, queries, value pool and every relation descriptor.
The native numeric ABI and private-map ownership remain explicit boundaries;
neither is established by generated-source equality. -/
namespace Ascent.ProjectionRowTransfer
open Ascent.WeightedCapacity.IntegerRowTransfer

def eligible (capacity width : Nat) (rows : List (List Int)) : Bool :=
  decide (0 < width) && !rows.isEmpty &&
    decide (2 + rows.length * width ≤ min capacity upper.toNat) && rows.all fun row =>
    decide (row.length = width) && row.all fun value =>
      decide (lower ≤ value ∧ value ≤ upper)

inductive EncodedRows where
  | ordinary (rows : List (List Int))
  | integer (width count : Nat) (cells : List Int)
  deriving Repr, DecidableEq

def packetSelected (requested supported : Bool) : Bool := requested && supported

def encode (requested : Bool) (capacity width : Nat) (rows : List (List Int)) : EncodedRows :=
  if packetSelected requested (eligible capacity width rows)
    then .integer width rows.length rows.flatten
  else .ordinary rows

def decode : EncodedRows → Option (List (List Int))
  | .ordinary rows => some rows
  | .integer width count cells => unpack width count cells

theorem encode_decode (requested : Bool) (capacity width : Nat) (rows : List (List Int)) :
    decode (encode requested capacity width rows) = some rows := by
  unfold encode packetSelected
  split
  · rename_i selected
    have chosen : requested = true ∧ eligible capacity width rows = true := by
      simpa only [Bool.and_eq_true] using selected
    have allowed : eligible capacity width rows = true := chosen.2
    have allRows : rows.all (fun row => decide (row.length = width) &&
        row.all (fun value => decide (lower ≤ value ∧ value ≤ upper))) = true := by
      have parts := allowed
      simp only [eligible, Bool.and_eq_true] at parts
      exact parts.2
    apply unpack_flatten
    intro row member
    have checked := List.all_eq_true.mp allRows row member
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checked
    exact checked.1
  · rfl

theorem no_opt_in (capacity width : Nat) (rows : List (List Int)) :
    encode false capacity width rows = .ordinary rows := by simp [encode, packetSelected]

theorem unsupported_identity (requested : Bool) (capacity width : Nat) (rows : List (List Int))
    (unsupported : eligible capacity width rows = false) :
    encode requested capacity width rows = .ordinary rows := by
  simp [encode, packetSelected, unsupported]

def encodeRelation {Metadata : Type} (requested : Bool) (capacity : Nat)
    (relation : Metadata × Nat × List (List Int)) : Metadata × EncodedRows :=
  (relation.1, encode requested capacity relation.2.1 relation.2.2)

def decodeRelation {Metadata : Type} (relation : Metadata × EncodedRows) :
    Option (Metadata × List (List Int)) :=
  (decode relation.2).map fun rows => (relation.1, rows)

theorem relation_metadata_and_rows {Metadata : Type} (requested : Bool) (capacity : Nat)
    (relation : Metadata × Nat × List (List Int)) :
    decodeRelation (encodeRelation requested capacity relation) =
      some (relation.1, relation.2.2) := by
  simp [decodeRelation, encodeRelation, encode_decode]

theorem catalogue_order_duplicates_and_metadata {Metadata Catalogue : Type}
    (metadata : Catalogue) (requested : Bool) (capacity : Nat)
    (relations : List (Metadata × Nat × List (List Int))) :
    (metadata, (relations.map (encodeRelation requested capacity)).mapM decodeRelation) =
      (metadata, some (relations.map fun relation => (relation.1, relation.2.2))) := by
  congr 1
  induction relations with
  | nil => rfl
  | cons relation rest ih =>
    simp [relation_metadata_and_rows, ih]

inductive Shape where
  | ordinary | sourceEnvelope | sourceResult | relations | rowSet
  | program | programRelations | programRelation
  deriving Repr, DecidableEq, BEq

def shapes : List Shape := [.ordinary, .sourceEnvelope, .sourceResult, .relations,
  .rowSet, .program, .programRelations, .programRelation]

def rustName : Shape → String
  | .ordinary => "Ordinary" | .sourceEnvelope => "SourceEnvelope"
  | .sourceResult => "SourceResult" | .relations => "Relations"
  | .rowSet => "RowSet" | .program => "Program"
  | .programRelations => "ProgramRelations" | .programRelation => "ProgramRelation"

def fieldRoutes : List (Shape × Option String × Shape) :=
  [(.sourceResult, some "relations", .relations),
   (.sourceResult, some "program", .program),
   (.relations, none, .rowSet),
   (.program, some "relations", .programRelations),
   (.programRelation, some "rows", .rowSet)]

def elementRoutes : List (Shape × Option Nat × Shape) :=
  [(.sourceEnvelope, some 1, .sourceResult), (.programRelations, none, .programRelation)]

/-- Group equal targets for Rust's match-arm style rule. The proved selection
equality below checks the reordering, rather than assuming it is harmless. -/
def groupedFieldRoutes : List (Shape × List (Shape × Option String × Shape)) :=
  (fieldRoutes.map (·.2.2)).eraseDups.map fun target =>
    (target, fieldRoutes.filter fun item => decide (item.2.2 = target))

def route {Key : Type} [DecidableEq Key] (routes : List (Shape × Option Key × Shape))
    (shape : Shape) (key : Key) : Shape :=
  ((routes.find? fun item => decide (item.1 = shape) &&
    item.2.1.all (fun value => decide (value = key))).map (·.2.2)).getD .ordinary

def fieldChild := route fieldRoutes
def elementChild := route elementRoutes

theorem grouped_field_table : groupedFieldRoutes.flatMap (·.2) =
    [(.sourceResult, some "relations", .relations),
     (.sourceResult, some "program", .program),
     (.relations, none, .rowSet), (.programRelation, some "rows", .rowSet),
     (.program, some "relations", .programRelations)] := by decide

theorem grouped_field_selection (shape : Shape) (key : String) :
    route (groupedFieldRoutes.flatMap (·.2)) shape key = fieldChild shape key := by
  rw [grouped_field_table]
  cases shape <;> simp [fieldChild, route, fieldRoutes, List.find?]

theorem projection_path :
    fieldChild (elementChild (fieldChild
      (fieldChild (elementChild .sourceEnvelope 1) "program") "relations") 0) "rows"
      = .rowSet := by rfl

theorem result_path (relation : String) :
    fieldChild (fieldChild (elementChild .sourceEnvelope 1) "relations") relation =
      .rowSet := by rfl

theorem ordinary_field_opaque (key : String) : fieldChild .ordinary key = .ordinary := by rfl
theorem ordinary_element_opaque (index : Nat) : elementChild .ordinary index = .ordinary := by rfl

theorem program_metadata_opaque (key : String) (other : key ≠ "relations") :
    fieldChild .program key = .ordinary := by
  simp [fieldChild, route, fieldRoutes, List.find?, Ne.symm other]

theorem relation_metadata_opaque (key : String) (other : key ≠ "rows") :
    fieldChild .programRelation key = .ordinary := by
  simp [fieldChild, route, fieldRoutes, List.find?, Ne.symm other]

/-- Native call units only. This excludes packing, Rust allocations and GC;
the metadata and required independent resource executions are unchanged. -/
theorem fewer_projection_row_calls (metadata rows columns : Nat)
    (nonempty : 0 < rows) (positiveWidth : 0 < columns) :
    metadata + packedCalls < metadata + knownKindRowCalls rows columns := by
  unfold packedCalls knownKindRowCalls
  have factor : 8 ≤ 6 + 2 * columns := by omega
  have bound := Nat.mul_le_mul_left rows factor
  omega

def shapeIndex : Shape → Nat
  | .ordinary => 0 | .sourceEnvelope => 1 | .sourceResult => 2 | .relations => 3
  | .rowSet => 4 | .program => 5 | .programRelations => 6 | .programRelation => 7

def quintSource : String :=
  "  pure def projection_row_packet(requested: bool, supported: bool): bool =\n" ++
  "    requested and supported\n" ++
  "  pure def projection_element(shape: int, index: int): int =\n" ++
  String.join (elementRoutes.map fun (shape, key, target) =>
    "    if (shape == " ++ toString (shapeIndex shape) ++
      (key.map fun value => " and index == " ++ toString value).getD "" ++
      ") " ++ toString (shapeIndex target) ++ " else\n") ++ "    0\n" ++
  "  pure def projection_field(shape: int, key: str): int =\n" ++
  String.join (fieldRoutes.map fun (shape, key, target) =>
    "    if (shape == " ++ toString (shapeIndex shape) ++
      (key.map fun value => " and key == \"" ++ value ++ "\"").getD "" ++
      ") " ++ toString (shapeIndex target) ++ " else\n") ++ "    0\n"

def schemeSource : String :=
  "(def (pack-projection-rows! program requested)\n" ++
  "  ;; Only fresh private wire dictionaries enter here, after complete capture.\n" ++
  "  (when requested\n" ++
  "    (for-each\n" ++
  "      (lambda (relation)\n" ++
  "        (let (packet (pack-integer-rows (hash-ref relation \"rows\")))\n" ++
  "          (when packet (hash-put! relation \"rows\" packet))))\n" ++
  "      (hash-ref program \"relations\")))\n" ++
  "  program)\n"

def rustSource : String :=
  "#[derive(Clone, Copy)]\nenum ReplyShape {\n" ++
  String.join (shapes.map fun shape => "    " ++ rustName shape ++ ",\n") ++
  "}\n\nimpl ReplyShape {\n    fn element_child(self, index: usize) -> Self {\n" ++
  "        match (self, index) {\n" ++
  String.join (elementRoutes.map fun (shape, key, target) =>
    "            (Self::" ++ rustName shape ++ ", " ++
      (key.map toString).getD "_" ++ ") => Self::" ++ rustName target ++ ",\n") ++
  "            _ => Self::Ordinary,\n        }\n    }\n\n" ++
  "    fn field_child(self, key: &str) -> Self {\n        match (self, key) {\n" ++
  String.join (groupedFieldRoutes.map fun (target, entries) =>
    "            " ++ String.intercalate " | " (entries.map fun (shape, key, _) =>
      "(Self::" ++ rustName shape ++ ", " ++
        (key.map fun value => "\"" ++ value ++ "\"").getD "_" ++ ")") ++
      " => Self::" ++ rustName target ++ ",\n") ++
  "            _ => Self::Ordinary,\n        }\n    }\n}\n"

end Ascent.ProjectionRowTransfer
