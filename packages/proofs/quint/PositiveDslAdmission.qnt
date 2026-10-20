// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Conditional protocol model: the selected rule constructors are pure.
// Source rendering and Scheme tests bind the capture frame; this is not a
// proof of Gerbil expansion, the recognizer, or the native Contract engine.
module PositiveDslAdmission {
  const Mutation: str
  type State = {phase: str, pending: int, borrowed: bool,
    callbackInside: bool, checked: bool, published: bool}
  var q: State
  action init = q' = {phase: "capture", pending: 2, borrowed: false,
    callbackInside: false, checked: false, published: false}
  action Capture = all {
    q.pending > 0,
    q.phase == "capture" or (Mutation == "early" and q.phase == "construct"),
    q' = {...q, pending: q.pending - 1,
      callbackInside: q.callbackInside or q.borrowed}}
  action CaptureFailure = all {q.phase == "capture",
    q' = {...q, phase: "terminal"}}
  action Begin = all {q.phase == "capture",
    q.pending == 0 or Mutation == "early",
    q' = {...q, phase: "construct", borrowed: true}}
  action Construct = all {q.phase == "construct", q.pending == 0,
    q' = {...q, phase: "check", borrowed: false}}
  action ConstructionFailure = all {q.phase == "construct",
    q' = {...q, phase: "terminal", borrowed: Mutation == "leak"}}
  action RootCheck = { nondet accepted = Set(false, true).oneOf(); all {
    q.phase == "check", q' = {...q, phase: "terminal",
      checked: Mutation != "skip-root", published: accepted}}}
  action Idle = all {q.phase == "terminal", q' = q}
  action step = any {Capture, CaptureFailure, Begin, Construct,
    ConstructionFailure, RootCheck, Idle}
  val CallbacksOutside = not(q.callbackInside)
  val ScopeRestored = q.phase != "terminal" or not(q.borrowed)
  val PublicationChecked = not(q.published) or q.checked
  val FullEvaluationMatrix = 512 * 2 * (1 + 2) == 3072
}
