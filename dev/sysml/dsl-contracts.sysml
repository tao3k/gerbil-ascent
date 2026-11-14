// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package AscentDsl {
    private import ScalarValues::*;
    doc /* DSL contracts with a Scheme implementation candidate. Fixture
       validation is not native acceptance or complete source refinement. */

    requirement relationRoleRequirement {
        doc /* DSL-ROLE: external updates and rule heads require their declared
           permissions; updates additionally require the admitted handle. */
    }
    requirement finiteDomainRequirement {
        doc /* DSL-DOMAIN: finite-height claims require discharged rank/domain
           premises; exhausting any execution budget cannot publish closure. */
    }
    requirement diagnosticRequirement {
        doc /* DSL-DIAGNOSTIC: source-origin transport preserves rejection,
           getter order and the absence of runnable state after rejection. */
    }
    // Allocation links express design responsibility, not satisfaction evidence.
    dependency roleAllocation from AscentDevelopment::relationRoles to relationRoleRequirement;
    dependency domainAllocation from AscentDevelopment::finiteDomains to finiteDomainRequirement;
    dependency diagnosticAllocation from AscentDevelopment::sourceDiagnostics to diagnosticRequirement;

    part def RelationRole {
        attribute acceptsExternalFacts : Boolean;
        attribute acceptsRuleHeads : Boolean;
        attribute writableHandle : Boolean;
        attribute updateRequested : Boolean;
        attribute updateAccepted : Boolean;
        attribute headRequested : Boolean;
        attribute headAccepted : Boolean;
        assert constraint declaredUpdatePermission {
            updateAccepted == (updateRequested and acceptsExternalFacts and writableHandle)
        }
        assert constraint declaredHeadPermission {
            headAccepted == (headRequested and acceptsRuleHeads)
        }
    }
    part def InputRelation :> RelationRole {
        attribute :>> acceptsExternalFacts default = true;
        attribute :>> acceptsRuleHeads default = false;
        attribute :>> writableHandle default = true;
        attribute :>> updateRequested default = true;
        attribute :>> updateAccepted default = true;
        attribute :>> headRequested default = false;
        attribute :>> headAccepted default = false;
    }
    part inputUpdate : InputRelation;
    part hiddenInput : InputRelation {
        attribute :>> writableHandle = false;
        attribute :>> updateAccepted = false;
    }
    part derivedUpdateRejected : InputRelation {
        attribute :>> acceptsExternalFacts = false;
        attribute :>> acceptsRuleHeads = true;
        attribute :>> updateAccepted = false;
        attribute :>> headRequested = true;
        attribute :>> headAccepted = true;
    }
    part mixedRelation : InputRelation {
        attribute :>> acceptsRuleHeads = true;
        attribute :>> headRequested = true;
        attribute :>> headAccepted = true;
    }
    part illegalDerivedUpdate : InputRelation { attribute :>> acceptsExternalFacts = false; }
    part leakedWriteHandle : InputRelation { attribute :>> writableHandle = false; }
    part illegalInputHead : InputRelation {
        attribute :>> headRequested = true;
        attribute :>> headAccepted = true;
    }

    part def FiniteClosure {
        attribute finiteHeightClaimed : Boolean;
        attribute domainClosed : Boolean;
        attribute monotoneStep : Boolean;
        attribute boundedRankProgress : Boolean;
        attribute executionBudgetPresent : Boolean;
        attribute exhausted : Boolean;
        attribute completedResultPublished : Boolean;
        assert constraint finiteHeightPremises {
            not finiteHeightClaimed or (domainClosed and monotoneStep and boundedRankProgress)
        }
        assert constraint budgetIsNotCompletion {
            not exhausted or not completedResultPublished
        }
        assert constraint executionRemainsBounded { executionBudgetPresent }
    }
    part def FiniteFixture :> FiniteClosure {
        attribute :>> finiteHeightClaimed default = true;
        attribute :>> domainClosed default = true;
        attribute :>> monotoneStep default = true;
        attribute :>> boundedRankProgress default = true;
        attribute :>> executionBudgetPresent default = true;
        attribute :>> exhausted default = false;
        attribute :>> completedResultPublished default = true;
    }
    part boundedDomain : FiniteFixture;
    part exhaustedFinite : FiniteFixture {
        attribute :>> exhausted = true;
        attribute :>> completedResultPublished = false;
    }
    part guardedUnbounded : FiniteFixture {
        attribute :>> finiteHeightClaimed = false;
        attribute :>> domainClosed = false;
        attribute :>> boundedRankProgress = false;
        attribute :>> exhausted = true;
        attribute :>> completedResultPublished = false;
    }
    part budgetAsTermination : FiniteFixture { attribute :>> boundedRankProgress = false; }
    part truncatedPublication : FiniteFixture { attribute :>> exhausted = true; }
    part droppedBudget : FiniteFixture { attribute :>> executionBudgetPresent = false; }

    part def DiagnosticTransport {
        attribute originalRejected : Boolean;
        attribute reportedRejected : Boolean;
        attribute originPreserved : Boolean;
        attribute callbackOrderPreserved : Boolean;
        attribute rejectedStateRunnable : Boolean;
        assert constraint verdictPreserved { originalRejected == reportedRejected }
        assert constraint originRetained { originPreserved }
        assert constraint observationOrder { callbackOrderPreserved }
        assert constraint rejectionNotRunnable {
            not reportedRejected or not rejectedStateRunnable
        }
    }
    part def DiagnosticFixture :> DiagnosticTransport {
        attribute :>> originalRejected default = true;
        attribute :>> reportedRejected default = true;
        attribute :>> originPreserved default = true;
        attribute :>> callbackOrderPreserved default = true;
        attribute :>> rejectedStateRunnable default = false;
    }
    part mappedRejection : DiagnosticFixture;
    part swallowedFailure : DiagnosticFixture { attribute :>> reportedRejected = false; }
    part lostOrigin : DiagnosticFixture { attribute :>> originPreserved = false; }
    part reorderedGetter : DiagnosticFixture { attribute :>> callbackOrderPreserved = false; }
    part runnableRejection : DiagnosticFixture { attribute :>> rejectedStateRunnable = true; }
}
