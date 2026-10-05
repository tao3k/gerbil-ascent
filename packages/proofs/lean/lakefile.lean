-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lake
open Lake DSL

package «gerbil-ascent-proof» where
  version := v!"0.1.0"

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "02da82f00ccb7012e33d1ac8c79e4ff791e7dac4"

@[default_target]
lean_lib AscentProof where
  roots := #[`AscentProof, `CappedArithmetic, `DescriptorScope,
             `FiniteHeight, `FiniteOperators, `LexicalLowering,
             `NativeSessionPublication, `PositiveNonmembership,
             `RecursiveLowering, `SessionPublication,
             `StratifiedNegation, `SourceCertificates]

lean_lib AscentProofTests where
  roots := #[`AscentProofTests]
