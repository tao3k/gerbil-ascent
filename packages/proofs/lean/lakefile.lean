-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lake
open Lake DSL

package «gerbil-ascent-proof» where
  version := v!"0.1.0"

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "247d1d6094b6af1bb873f69564b271bc978730ed"

@[default_target]
lean_lib AscentProof where
  roots := #[`AscentProof, `AtomicBinding, `CappedArithmetic, `DependencyInvalidation, `DescriptorScope,
             `FunctionalDependency, `EquivalenceComponents,
             `FiniteHeight, `FiniteOperators, `LexicalLowering,
             `NativeBitmapWorklist, `NativeGraphWorklist,
             `PositiveNonmembership,
             `RecursiveLowering,
             `StratifiedNegation, `SourceCertificates, `SourceUpdateFrame, `RoundAdmission,
             `RuleGraphClosure, `RuleBodyFrame, `PositiveSlots, `PositiveTraversal, `IndexedPositiveTraversal, `IndexedIteration, `ComponentClosure, `GroundedBinding, `ComponentProjection, `SnapshotClosure, `ProviderFrontier, `SemiNaive, `PositiveConsequence, `TransitiveComponents]

lean_lib AscentProofTests where
  roots := #[`Tests.AscentProofTests, `Tests.RuleBodyFrameTests, `Tests.PositiveSlotsTests, `Tests.PositiveTraversalTests, `Tests.PositiveConsequenceTests, `Tests.IndexedPositiveTraversalTests, `Tests.IndexedIterationTests, `Tests.ComponentClosureTests, `Tests.GroundedBindingTests, `Tests.ComponentProjectionTests, `Tests.SnapshotClosureTests, `Tests.EquivalenceComponentsTests]
