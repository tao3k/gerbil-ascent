-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lake
open Lake DSL

package «gerbil-ascent-proof» where
  version := v!"0.1.0"
  weakLeanArgs := #["-j2"]

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "v0.1.2"

@[default_target]
lean_lib AscentProof where
  roots := #[`FiniteChoice, `OrderedExportGraph, `WeightedExportCapacity, `UfMergeFootprint, `DslDeclarations, `OwnerAdmission, `LookupCost, `CompilerCost, `PreparationWork, `DescriptorKeys, `DescriptorStream, `DescriptorKernel, `SchemeDescriptor, `RustDescriptor, `CachePublication, `ActorEnvelope, `SccState, `ExecutionPolicy, `ExecutionRendering, `ScheduledExecution, `CompiledCertificate, `PhysicalBuckets, `RayonPublication, `ClosedDslLowering, `MinimumHeight, `StableSourceSupport, `SourceOccurrences, `OrderedMapping, `AscentProof, `DerivationCounts, `CanonicalIndex, `Withholding, `ExecutionFeedback, `UnsanitizedPaths, `ProofDag, `BoundedSpine, `TerminalTraversal, `NumericReduction, `CountReduction, `CertificateMaterial, `AtomicBinding, `CappedArithmetic, `DependencyInvalidation, `DescriptorScope,
             `FiniteFlowPacking, `PoloniusInitialization, `ProviderRectangles, `ProviderRouting, `CurriedDictionary, `ProviderEncoding, `ProviderAdmission, `ProviderIteration, `LatticeProjection, `StrictDependencies, `PendingKeys, `LatticeAdmission, `PipeCapture, `FunctionalDependency, `EquivalenceComponents, `DirectedFrontier,
             `ScopedWitness, `BranchScopedWitness, `ScopedCompositionSpec, `ScopedComposition, `ScopedReachabilityMask, `ScopedQuerySpec, `ScopedQuery, `MovieCastQuery, `MaterializedMovieQuery, `RetainedInference, `FeedbackConformance, `FiniteHeight, `FiniteOperators, `LexicalLowering,
             `BitmapWorklist, `GraphWorklist, `PositiveNonmembership,
             `RecursiveLowering,
             `StratifiedNegation, `SourceCertificates, `SourceUpdateFrame, `RoundAdmission,
             `RuleGraphClosure, `RuleBodyFrame, `PositiveSlots, `ScalarEncoding, `PositiveTraversal, `IndexedPositiveTraversal, `IndexedIteration, `ComponentClosure, `GroundedBinding, `ComponentProjection, `SnapshotClosure, `ProviderFrontier, `SemiNaive, `PositiveConsequence, `TransitiveComponents]

lean_lib AscentProofTests where
  roots := #[`Tests.MinimumHeightTests, `Tests.StableSourceSupportTests, `Tests.SourceOccurrencesTests, `Tests.OrderedMappingTests, `Tests.DerivationCountsTests, `Tests.CanonicalIndexTests, `Tests.WithholdingTests, `Tests.ExecutionFeedbackTests, `Tests.UnsanitizedPathsTests, `Tests.ProofDagTests, `Tests.BoundedSpineTests, `Tests.TerminalTraversalTests, `Tests.NumericReductionTests, `Tests.CountReductionTests, `Tests.NegativeProbeTests, `Tests.CertificateMaterialTests, `Tests.FiniteFlowPackingTests, `Tests.PoloniusInitializationTests, `Tests.AscentProofTests, `Tests.RuleBodyFrameTests, `Tests.PositiveSlotsTests, `Tests.ScalarEncodingTests, `Tests.PositiveTraversalTests, `Tests.PositiveConsequenceTests, `Tests.IndexedPositiveTraversalTests, `Tests.IndexedIterationTests, `Tests.ComponentClosureTests, `Tests.GroundedBindingTests, `Tests.ComponentProjectionTests, `Tests.SnapshotClosureTests, `Tests.EquivalenceComponentsTests, `Tests.DirectedFrontierTests, `Tests.ProviderRectanglesTests, `Tests.ProviderRoutingTests, `Tests.CurriedDictionaryTests, `Tests.TransitiveComponentsTests, `Tests.ProviderEncodingTests, `Tests.ProviderAdmissionTests, `Tests.ProviderIterationTests, `Tests.LatticeProjectionTests, `Tests.StrictDependenciesTests, `Tests.PendingKeysTests, `Tests.LatticeAdmissionTests, `Tests.PipeCaptureTests]
