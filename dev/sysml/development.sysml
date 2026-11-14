// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package AscentDevelopment {
    private import ScalarValues::*;
    doc /* Development-only assurance contracts. Fixture fields are declared
       assumptions, not observations, theorem receipts or source extraction.
       See workflow.org for actual ownership and unclosed obligations. */

    part def Workstream {
        attribute requirementId : String;
        attribute designPath : String;
        attribute schemePath : String;
        attribute proofObligation : String;
        attribute temporalObligation : String;
        attribute nativeDiscriminator : String;
        attribute remainingGap : String;
    }
    part relationRoles : Workstream {
        attribute :>> requirementId = "DSL-ROLE";
        attribute :>> designPath = "dev/sysml/workflow.org#dsl-role";
        attribute :>> schemePath = "program/scheme-language.ss; program/scheme-session.ss";
        attribute :>> proofObligation = "DslDeclarations: permission/filter/composition laws; Scheme decoding still OPEN";
        attribute :>> temporalObligation = "SessionTransaction: existing publication/rollback model only";
        attribute :>> nativeDiscriminator = "scheme-declaration-contract-test.ss: parity, illegal heads/updates, mixed supports";
        attribute :>> remainingGap = "Local 177-module acceptance passed; complete decoder refinement and release/performance acceptance OPEN";
    }
    part finiteDomains : Workstream {
        attribute :>> requirementId = "DSL-DOMAIN";
        attribute :>> designPath = "dev/sysml/workflow.org#dsl-domain";
        attribute :>> schemePath = "program/scheme-checked.ss; program/higher-order.ss";
        attribute :>> proofObligation = "FiniteHeight.bounded_rank_stabilizes under bounded-rank/progress premises";
        attribute :>> temporalObligation = "SessionTransaction: existing rollback model only";
        attribute :>> nativeDiscriminator = "scheme-higher-order-test.ss; scheme-closure-contract-test.ss";
        attribute :>> remainingGap = "Macro annotations natively tested; general source refinement and release acceptance OPEN";
    }
    part sourceDiagnostics : Workstream {
        attribute :>> requirementId = "DSL-DIAGNOSTIC";
        attribute :>> designPath = "dev/sysml/workflow.org#dsl-diagnostic";
        attribute :>> schemePath = "program/scheme-admit.ss; program/planning.ss";
        attribute :>> proofObligation = "DslDeclarations: origin erasure law; concrete callback/order correspondence OPEN";
        attribute :>> temporalObligation = "None new: diagnostic transport has no independent scheduler";
        attribute :>> nativeDiscriminator = "scheme-declaration-contract-test.ss: reader origin and imported input head rejection";
        attribute :>> remainingGap = "Reader spans natively tested; normalized presentation, expansion ancestry/cycle paths and source refinement OPEN";
    }

    part def CompletionClaim {
        attribute sourceClosureClaimed : Boolean;
        attribute representationProved : Boolean;
        attribute transitionRefined : Boolean;
        attribute nativeVerified : Boolean;
        attribute evidenceCurrent : Boolean;
        attribute performanceClaimed : Boolean;
        attribute matchedWorkloadMeasured : Boolean;
        assert constraint sourceEvidenceRequired {
            not sourceClosureClaimed or (representationProved and transitionRefined and
                nativeVerified and evidenceCurrent)
        }
        assert constraint measurementRequired {
            not performanceClaimed or (matchedWorkloadMeasured and evidenceCurrent)
        }
    }
    part def OpenWork :> CompletionClaim {
        attribute :>> sourceClosureClaimed default = false;
        attribute :>> representationProved default = false;
        attribute :>> transitionRefined default = false;
        attribute :>> nativeVerified default = false;
        attribute :>> evidenceCurrent default = false;
        attribute :>> performanceClaimed default = false;
        attribute :>> matchedWorkloadMeasured default = false;
    }
    part openObligations : OpenWork;
    part prematureSourceClosure : OpenWork { attribute :>> sourceClosureClaimed = true; }
    part unmeasuredSpeedup : OpenWork { attribute :>> performanceClaimed = true; }
}
