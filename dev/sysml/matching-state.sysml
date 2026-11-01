// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package AscentMatching {
    private import ScalarValues::*;
    doc /* Architectural contract study grounded in the local Dusa v3 paper.
       Current and proposed elements are separate. Boolean fixture claims are
       model inputs, not observations of Scheme execution or proof receipts. */

    package Current {
        part compiler {
            doc /* core/positive-plan.ss and core/positive-certificate.ss:
               immutable ordered action plan, slot layout and translation check. */
        }
        part evaluator {
            doc /* program/evaluate.ss: frozen round lanes, first-fresh pivots,
               engine-owned frames and bounded factorized old-prefix DAG state.
               This replaces the former rule/round first-atom special case. */
        }
        part indexes {
            doc /* program/index.ss: source/delta versioned exact indexes and
               old-lane selection. Index sharing is not join-prefix sharing. */
        }
        part session {
            doc /* program/session.ss, program/update-selection.ss, program/reuse.ss:
               accepted source snapshots, affected-component invalidation,
               completed-result reuse, atomic publication and failure recovery. */
        }
        part support {
            doc /* candidate/provenance-maintenance.ss and provenance-graph.ss:
               ordered grounded support alternatives; independent graph replay,
               not solver-emitted events. */
        }
        dependency checkedPlan from evaluator to compiler;
        dependency frozenRows from evaluator to indexes;
        dependency execution from session to evaluator;
    }

    part def PrefixSchema {
        attribute depth : Integer;
        attribute immutable : Boolean;
        attribute bindingLayoutChecked : Boolean;
        attribute supportLayoutChecked : Boolean;
        assert constraint nonemptyPrefix { depth > 0 }
    }

    part def ReuseDecision {
        // A depth-two dependency slice. The general n-atom law belongs in Lean.
        attribute reuseSelected : Boolean;
        attribute matchingComplete : Boolean;
        attribute immutableCut : Boolean;
        attribute pureOperators : Boolean;
        attribute schemaEqual : Boolean;
        attribute readerOwnerEqual : Boolean;
        attribute savedSource0 : Integer;
        attribute currentSource0 : Integer;
        attribute savedDelta0 : Integer;
        attribute currentDelta0 : Integer;
        attribute savedSource1 : Integer;
        attribute currentSource1 : Integer;
        attribute savedDelta1 : Integer;
        attribute currentDelta1 : Integer;
        assert constraint completedRead {
            not reuseSelected or (matchingComplete and immutableCut)
        }
        assert constraint semanticIdentity {
            not reuseSelected or (pureOperators and schemaEqual and readerOwnerEqual)
        }
        assert constraint everyPrefixDependency {
            not reuseSelected or
            (savedSource0 == currentSource0 and savedDelta0 == currentDelta0 and
             savedSource1 == currentSource1 and savedDelta1 == currentDelta1)
        }
    }

    part def BranchPublication {
        attribute sharedPrefixSelected : Boolean;
        attribute prefixComplete : Boolean;
        attribute prefixImmutable : Boolean;
        attribute leftMutableOwner : Integer;
        attribute rightMutableOwner : Integer;
        attribute queryComplete : Boolean;
        attribute suffixExpanded : Boolean;
        attribute fullSupportsRetained : Boolean;
        attribute canceled : Boolean;
        attribute publishSelected : Boolean;
        assert constraint immutableSharing {
            not sharedPrefixSelected or (prefixComplete and prefixImmutable)
        }
        assert constraint mutableIsolation { leftMutableOwner != rightMutableOwner }
        assert constraint completePublication {
            not publishSelected or
            (queryComplete and suffixExpanded and fullSupportsRetained and not canceled)
        }
    }

    package Target {
        doc /* Proposed organization, not another evaluator or public choice API.
           Prefix schemas belong to compiler IR; matching tables belong to an
           engine cut. Session owns publication, not a global matcher cache. */
        part prefixSchema : PrefixSchema {
            attribute :>> depth = 2;
            attribute :>> immutable = true;
            attribute :>> bindingLayoutChecked = false;
            attribute :>> supportLayoutChecked = false;
        }
        part prefixTable {
            doc /* Ordered successful environments plus full supporting row
               occurrences. Repeated values do not erase alternative supports. */
        }
        part deltaScheduler {
            doc /* For pivot p: old lanes before p, delta at p, total after p.
               Reuse a matching prefix; never reuse an old suffix failure. */
        }
        part resultPublication {
            doc /* Existing Session commits a completed result or preserves the
               previous result on failure. Local join completion is not closure. */
        }
        dependency schema from prefixTable to prefixSchema;
        dependency continuation from deltaScheduler to prefixTable;
        dependency publish from resultPublication to deltaScheduler;
        part admission {
            attribute nativeRefinementAccepted : Boolean = false;
            attribute crossRuleSharingAccepted : Boolean = false;
            attribute retainedPrefixSharingAccepted : Boolean = false;
            attribute performanceAccepted : Boolean = false;
        }
    }

    part matchingOnly : BranchPublication {
        attribute :>> sharedPrefixSelected = true;
        attribute :>> prefixComplete = true;
        attribute :>> prefixImmutable = true;
        attribute :>> leftMutableOwner = 1;
        attribute :>> rightMutableOwner = 2;
        attribute :>> queryComplete = false;
        attribute :>> suffixExpanded = false;
        attribute :>> fullSupportsRetained = true;
        attribute :>> canceled = false;
        attribute :>> publishSelected = false;
    }
    part def CompletedPublication :> BranchPublication {
        attribute :>> sharedPrefixSelected default = true;
        attribute :>> prefixComplete default = true;
        attribute :>> prefixImmutable default = true;
        attribute :>> leftMutableOwner default = 1;
        attribute :>> rightMutableOwner default = 2;
        attribute :>> queryComplete default = true;
        attribute :>> suffixExpanded default = true;
        attribute :>> fullSupportsRetained default = true;
        attribute :>> canceled default = false;
        attribute :>> publishSelected default = true;
    }
    part newSuffix : CompletedPublication;
    part def CompletedReuse :> ReuseDecision {
        attribute :>> reuseSelected default = true;
        attribute :>> matchingComplete default = true;
        attribute :>> immutableCut default = true;
        attribute :>> pureOperators default = true;
        attribute :>> schemaEqual default = true;
        attribute :>> readerOwnerEqual default = true;
        attribute :>> savedSource0 default = 3;
        attribute :>> currentSource0 default = 3;
        attribute :>> savedDelta0 default = 1;
        attribute :>> currentDelta0 default = 1;
        attribute :>> savedSource1 default = 5;
        attribute :>> currentSource1 default = 5;
        attribute :>> savedDelta1 default = 2;
        attribute :>> currentDelta1 default = 2;
    }
    part sameCut : CompletedReuse;
    // Negative fixtures are checked explicitly; they are not satisfaction claims.
    part staleSecondSource : CompletedReuse {
        attribute :>> currentSource1 = 6;
    }
    part staleSecondDelta : CompletedReuse {
        attribute :>> currentDelta1 = 3;
    }
    part wrongOwner : CompletedReuse {
        attribute :>> readerOwnerEqual = false;
    }
    part incompletePrefix : CompletedReuse {
        attribute :>> matchingComplete = false;
    }
    part lostSupport : CompletedPublication {
        attribute :>> fullSupportsRetained = false;
    }
    part skippedSuffix : CompletedPublication {
        attribute :>> suffixExpanded = false;
    }
    part sharedMutation : CompletedPublication {
        attribute :>> rightMutableOwner = 1;
    }
    part canceledPublication : CompletedPublication {
        attribute :>> canceled = true;
    }
    // Factorized transitions differ from a fully materialized P[i]. Their
    // incoming environment is supplied by the current prefix, never restored
    // together with an obsolete caller support path.
    part def TransitionRead {
        attribute reuseSelected : Boolean;
        attribute pureOperators : Boolean;
        attribute canonicalSchemaEqual : Boolean;
        attribute incomingBindingsEqual : Boolean;
        attribute localSourceDeltaCutEqual : Boolean;
        attribute indexOwnerEqual : Boolean;
        attribute complete : Boolean;
        attribute callerSupportCached : Boolean;
        assert constraint exactTransitionRead {
            not reuseSelected or (pureOperators and canonicalSchemaEqual and incomingBindingsEqual and
              localSourceDeltaCutEqual and indexOwnerEqual and complete and not callerSupportCached)
        }
    }
    part def TransitionFixture :> TransitionRead {
        attribute :>> reuseSelected default = true;
        attribute :>> pureOperators default = true;
        attribute :>> canonicalSchemaEqual default = true;
        attribute :>> incomingBindingsEqual default = true;
        attribute :>> localSourceDeltaCutEqual default = true;
        attribute :>> indexOwnerEqual default = true;
        attribute :>> complete default = true;
        attribute :>> callerSupportCached default = false;
    }
    part def RetentionPolicy {
        attribute capacity : Integer;
        attribute retained : Integer;
        attribute retentionRefused : Boolean;
        attribute streamingContinues : Boolean;
        attribute publicFactBudgetUnchanged : Boolean;
        assert constraint boundedRetention { capacity >= 0 and retained >= 0 and retained <= capacity }
        assert constraint exactFallback { not retentionRefused or streamingContinues }
        assert constraint separateBudgets { publicFactBudgetUnchanged }
    }
    part transitionReplay : TransitionFixture;
    part effectfulReuse : TransitionFixture { attribute :>> pureOperators = false; }
    part changedBinding : TransitionFixture { attribute :>> incomingBindingsEqual = false; }
    part staleLocalCut : TransitionFixture { attribute :>> localSourceDeltaCutEqual = false; }
    part cachedCallerSupport : TransitionFixture { attribute :>> callerSupportCached = true; }
    part streamingAtCapacity : RetentionPolicy {
        attribute :>> capacity default = 8;
        attribute :>> retained default = 8;
        attribute :>> retentionRefused default = true;
        attribute :>> streamingContinues default = true;
        attribute :>> publicFactBudgetUnchanged default = true;
    }
    part overCapacity : RetentionPolicy {
        attribute :>> capacity = 8;
        attribute :>> retained = 9;
        attribute :>> retentionRefused = false;
        attribute :>> streamingContinues = true;
        attribute :>> publicFactBudgetUnchanged = true;
    }
    part droppedFallback : RetentionPolicy {
        attribute :>> capacity = 8;
        attribute :>> retained = 0;
        attribute :>> retentionRefused = true;
        attribute :>> streamingContinues = false;
        attribute :>> publicFactBudgetUnchanged = true;
    }
}
