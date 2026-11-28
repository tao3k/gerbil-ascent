// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorPackedSource {
  const Mutation: str
  type Row = (int, int)
  type State = {source: List[Row], cells: List[int], result: List[Row],
    bound: int, seed: bool, timed: bool, observed: bool, borrowed: bool, released: bool,
    delivered: List[Row], exitAt: int, widthLabel: int,
    affineInput: List[Row], affineAccepted: bool}
  var q: State

  val input = List((2, 11), (5, 17))
  val changed = List((2, 99), (5, 17))

  pure def pack(rows: List[Row]): List[int] =
    rows.foldl(List(), (cells, row) => cells.append(row._1).append(row._2))

  pure def view(cells: List[int]): List[Row] =
    List((cells.nth(0), cells.nth(1)), (cells.nth(2), cells.nth(3)))

  action init = {
    nondet bound = Set(1, 2).oneOf()
    nondet seed = Set(true, false).oneOf()
    nondet timed = Set(true, false).oneOf()
    nondet observed = Set(true, false).oneOf()
    nondet widthLabel = Set(-129, -128, -1, 0, 127, 128).oneOf()
    q' = {source: input, cells: pack(input), result: List(), bound: bound,
      seed: seed, timed: timed, observed: observed, borrowed: false, released: false,
      delivered: List(), exitAt: -1, widthLabel: widthLabel,
      affineInput: List(), affineAccepted: false}
  }

  action execute = {
    val allowed = (q.bound >= 2 or Mutation == "omit-budget")
      and (not(q.seed) or Mutation == "accept-seed")
      and (not(q.timed) or Mutation == "accept-deadline")
      and (not(q.observed) or Mutation == "accept-observed")
    all {
      q.result.length() == 0, not(q.released),
      q' = {...q, borrowed: allowed,
        result: if (allowed) view(q.cells) else List((0, 0))}
    }
  }

  action editCaller = all {
    q.source == input,
    q' = {...q, source: changed,
      cells: if (Mutation == "borrow-caller") pack(changed) else q.cells}
  }

  action release = all {
    q.borrowed, not(q.released),
    q' = {...q, released: true, result: if (Mutation == "reverse-output")
      List(q.result.nth(1), q.result.nth(0)) else q.result}
  }

  action deliver = {
    val cursor = q.delivered.length()
    val rows = if (Mutation == "follow-new-source") q.source else view(q.cells)
    val row = if (cursor < rows.length()) rows.nth(cursor) else (0, 0)
    val emitted = if (Mutation == "wrong-field") (row._1, row._1) else row
    all {
      q.borrowed, cursor < rows.length(),
      q.exitAt == -1 or Mutation == "read-after-exit",
      q' = {...q, delivered: q.delivered.append(emitted)}
    }
  }

  action exitConsumer = all {
    q.borrowed, q.exitAt == -1, q.delivered.length() < 2,
    q' = {...q, exitAt: q.delivered.length()}
  }

  action step = any {execute, editCaller, release, deliver, exitConsumer, captureAffine}
  val ExactEligibility = not(q.borrowed)
    or (q.bound >= 2 and not(q.seed) and not(q.timed) and not(q.observed))
  val CapturedValues = view(q.cells) == input
  val ExactExport = not(q.borrowed) or q.result == input
  val ExpectedDelivery = q.delivered == List() or q.delivered == List(input.nth(0))
    or q.delivered == input
  val StopsAtExit = q.exitAt == -1 or q.delivered.length() == q.exitAt
  val PackedReuseExact =
    val matches = if (Mutation == "match-size-only") q.source.length() == input.length()
      else pack(q.source) == pack(input)
    not(matches) or q.source == input

  // The protocol checker uses an eight-bit instance of the width guard.
  // Lean and the native tests check the actual signed 32-bit boundaries.
  pure def storedSignedCell(label: int): int =
    if ((label >= -128 and label < 128) or Mutation == "narrow-wide-label")
      (label + 128) % 256 - 128
    else label

  val PackedWidthExact = storedSignedCell(q.widthLabel) == q.widthLabel

  // Include both signs, a constant value column and a candidate whose last
  // tuple differs. The runtime scans the full finite source before keeping
  // a progression in place of its packed cells.
  val affineCases = Set(
    List((9, -4), (6, 1), (3, 6)),
    List((0, 5), (4, 5), (8, 5)),
    List((9, -4), (6, 1), (3, 7)))

  pure def affineRow(rows: List[Row], ordinal: int): Row = {
    val first = rows.nth(0)
    val second = rows.nth(1)
    (first._1 + ordinal * (second._1 - first._1),
     first._2 + ordinal * (second._2 - first._2))
  }

  action captureAffine = {
    nondet rows = affineCases.oneOf()
    val admitted = rows.nth(0)._1 != rows.nth(1)._1
      and rows.indices().forall(i =>
        (Mutation == "omit-affine-last" and i == rows.length() - 1)
          or affineRow(rows, i) == rows.nth(i))
    all {
      q.affineInput.length() == 0,
      q' = {...q, affineInput: rows, affineAccepted: admitted}
    }
  }

  val AffineCaptureExact = not(q.affineAccepted)
    or q.affineInput.indices().forall(i => affineRow(q.affineInput, i) == q.affineInput.nth(i))
}
