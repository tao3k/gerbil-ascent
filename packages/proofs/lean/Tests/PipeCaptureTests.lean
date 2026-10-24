-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PipeCapture
open Ascent.PipeCapture
example : (replay initial [.chunk [228],.interrupted,.chunk [184,173],.eof]).bytes = [228,184,173] := by decide
example : (replay initial [.chunk [1,2],.failed,.chunk [3]]).bytes = [1,2] := by decide
example : ¬ Admitted (replay initial [.chunk [1],.failed] : State Nat) true true := by unfold Admitted; decide
example : ¬ Admitted (replay initial [.chunk [1]] : State Nat) true true := by unfold Admitted; decide
#print axioms interrupted_inert
#print axioms terminal_replay
#print axioms live_payload_exact
#print axioms capture_exact
#print axioms partial_bytes_retained
#print axioms error_rejected
#print axioms missing_eof_rejected
#print axioms process_failure_rejected
#print axioms request_failure_rejected
