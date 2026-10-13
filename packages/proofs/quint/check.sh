#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
set -euo pipefail
group="${1:-all}"
models=(MinimumHeight WithdrawalConcurrency WithdrawalSession ChangePlan ActorRound ActorRoundCredits ActorSession ActorTestPool CertificateMaterial TerminalTraversal ExecutionFeedback Withholding CanonicalIndex DerivationCounts ProofShapeAdmission ProofPrefix ComponentIndex CountProbe LatticeProjection NativeSessionPublication NegativeProbe NumericProbe OracleTransport PositiveNonmembershipSession ProviderAdmission ProviderFrontier ProviderReplay ProviderRouting ProviderViews ReaderLifetime ReadyComponents SessionTransaction TransitiveComponents)
models+=(OwnedLookup WeightedExport RectangleCompaction RectangleExport ScopedWitness BranchScopedWitness ScopedComposition ScopedReachabilityMask ScopedQuery MovieCastQuery NativeEvidenceLifecycle NativeDslOwnership EvidenceCacheAdmission)
case "$group" in
  all) ;;
  Nonmembership) models=(CertificateMaterial TerminalTraversal ExecutionFeedback Withholding ProofShapeAdmission ProofPrefix CountProbe NegativeProbe NumericProbe PositiveNonmembershipSession SessionTransaction NativeSessionPublication) ;;
  ProviderViews) models=(ProviderViews ReaderLifetime RectangleExport RectangleCompaction WeightedExport OwnedLookup) ;;
  *) found=0; for model in "${models[@]}"; do if [[ "$model" = "$group" ]]; then found=1; fi; done; [[ "$found" = 1 ]] || { echo "Unknown Quint feature: $group" >&2; exit 2; }; models=("$group") ;;
esac
export QUINT_HOME="$PWD/.cache/ascent/tools/quint-backends"
export OUT_DIR="$PWD/.cache/ascent/quint-output"
export no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"
export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
quint=.cache/ascent/tools/quint/node_modules/.bin/quint
jar="$QUINT_HOME/apalache-dist-0.62.1/apalache/lib/apalache.jar"
retain_run=0
if [[ -n "${ASCENT_FORMAL_RUN_DIR:-}" ]]; then
  mkdir "$ASCENT_FORMAL_RUN_DIR"
  temp=$(cd "$ASCENT_FORMAL_RUN_DIR" && pwd)
  retain_run=1
else
  temp=$(mktemp -d)
fi
server_pid=
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  if [[ "$retain_run" = 0 ]]; then rm -rf "$temp"; fi
}
trap cleanup EXIT
cutoff="${ASCENT_FORMAL_GENERATION_CUTOFF:-2}"
actor_cutoff="${ASCENT_FORMAL_ACTOR_GENERATION_CUTOFF:-2}"
round_cutoff="${ASCENT_FORMAL_ROUND_CUTOFF:-4}"
session_cutoff="${ASCENT_FORMAL_SESSION_GENERATION_CUTOFF:-4}"
views_cutoff="${ASCENT_FORMAL_GENERATION_CUTOFF:-3}"
for bound in "$cutoff" "$actor_cutoff" "$round_cutoff" "$session_cutoff" "$views_cutoff"; do
  [[ "$bound" =~ ^[0-9]+$ ]] && ((bound >= 2)) || { echo 'Invalid finite exploration bound' >&2; exit 2; }
done
((session_cutoff >= 3 && round_cutoff >= 3))
configure() {
  main="$model"; specification=; constraint=; properties=
  case "$model" in
    ActorRound) constants="Workers = {1,2}\nGenerationCutoff = $actor_cutoff\nRoundCutoff = $round_cutoff\nMutation = \"none\""; invariants='CompletePublication NoStaleCompletion CompleteBarrier'; constraint=Exploration ;;
    ActorRoundCredits) constants='Tasks = {1,2,3}\nCapacity = 2\nEarlyReturn = FALSE'; invariants='Partition BoundedCredit BoundedAssigned CompleteReturn' ;;
    ActorTestPool) constants='Tasks = {1,2,3}\nCapacity = 2\nEarlyReturn = FALSE'; invariants='Partition BoundedCredits StoppedAdmission CompleteReturn' ;;
    ActorSession) constants="Cuts = {0,1}\nGenerationCutoff = $session_cutoff\nMutation = \"none\""; invariants='ConsistentPublication NoStalePublication DrainedClose'; constraint=Exploration ;;
    ComponentIndex) main=ComponentIndexFixture; constants='Fault = "none"'; invariants='Consistent PrivateExtension HeldStable ViewConsistent' ;;
    LatticeProjection) constants='Mutation = "none"\nRemaining = 2'; invariants='MapExact SnapshotExact PrivateStable HeldStable KeyCoverage BudgetBound RefusalSound RefusalStable' ;;
    NativeSessionPublication) constants="GenerationCutoff = $cutoff\nMutation = \"none\""; invariants='TypeOK CommittedSnapshot CleanAligned PartialBounded'; properties=NoPrematurePublication; constraint=ExplorationBound ;;
    NativeEvidenceLifecycle) constants="GenerationCutoff = $cutoff\nInputLimit = 0\nMutation = \"none\""; invariants='TypeOK CurrentResult IndependentExplanation FrozenObservation RejectionAtomic ClosedOwners'; constraint=ExplorationBound ;;
    NativeDslOwnership) constants='ScopeCapacity = 2\nMutation = "none"'; invariants='ChargedExpansion IsolatedDefinitions NoForeignReference LiveValues'; constraint=ExplorationBound ;;
    EvidenceCacheAdmission) constants='Mutation = "none"'; invariants='ExactSource ExactBackend ExactPolicy FailureRevoked LiveAdmission' ;;
    PositiveNonmembershipSession) constants="GenerationCutoff = $cutoff"; invariants='TypeOK NoStalePublished NoStaleUse'; constraint=ExplorationBound ;;
    SessionTransaction) constants="GenerationCutoff = $cutoff\nMutation = \"none\""; invariants='TypeOK AtomicSnapshot'; properties='NoStaleCommit AbortPreservesSnapshot'; constraint=ExplorationBound ;;
    OracleTransport) constants='Mutation = "none"'; invariants='ReaderErrorSound CompleteReaders ReaderClean CompleteBytes ExitAndRequest' ;;
    ProviderAdmission) main=ProviderAdmissionFixture; constants='Fault = "none"'; invariants='CountCaps MatchingExact OutputExact DetachedPacket NoEarlyCallbacks FailedCacheRevoked' ;;
    ProviderFrontier) main=ProviderFrontierFixture; constants='Fault = "none"\nSeeded = FALSE'; invariants='ExactFrontier FrontierComplete DeliveredExact ConsumerSnapshot' ;;
    ProviderReplay) constants='Nodes = {0,1}\nScopes = {0,1}\nMutation = "none"'; invariants='PublishedExact JournalExact OrderExact HeldExact RefusalAtomic' ;;
    ProviderRouting) constants='Mutation = "none"'; invariants=CompleteExact ;;
    WithdrawalSession) constants='Mutation = "none"'; invariants='AtomicSnapshot FrozenGraph CurrentTokens CurrentOrdinal CumulativeSupport HistoricalObservation SupportCoverage StorageAtomic BudgetAdmission'; constraint=ExplorationBound ;;
    MinimumHeight) constants='Mutation = "none"'; invariants='CompleteMinimum Private' ;;
    WithdrawalConcurrency) constants='Mutation = "none"\nSecondExpected = 0'; invariants='AtomicSnapshot ExclusiveOwnership TerminalReleased OnePublicationPerGeneration ReceiptBound' ;;
    ChangePlan) constants='Mutation = "none"'; invariants='Frozen CompletePublication FailureAtomic' ;;
    DerivationCounts) constants='Mutation = "none"'; invariants='Private Fixed Exact' ;;
    CanonicalIndex) constants='Mutation = "none"'; invariants='Private Canonical' ;;
    Withholding) constants='Mutation = "none"'; invariants='Private Bound Protected ExactCut' ;;
    ExecutionFeedback) constants='Mutation = "none"'; invariants='Qualified ExactDifferences ExactMatch InconclusivePrivate' ;;
    ScopedReachabilityMask) constants='Mutation = "none"'; invariants='ExactReach ExactWitnesses ExactBranches ExactGroups Private' ;;
    MovieCastQuery) constants='Mutation = "none"'; invariants='ExactEvidence ExactAnswer ExactTrace Private' ;;
    ScopedQuery) constants='Mutation = "none"'; invariants='ExactHops ExactReach ExactShortest ExactPredecessors ExactWitnesses ExactBranches ExactGroups ExactTraces Private' ;;
    ScopedComposition) constants='Mutation = "none"'; invariants='ExactWitnesses ExactCoverage ExactMissing ExactAnswer Private' ;;
    BranchScopedWitness) constants='Mutation = "none"'; invariants='ExactWitnesses ExactBranches ExactUnion Private' ;;
    ScopedWitness) constants='Mutation = "none"'; invariants='ExactWitnesses ExactAnswer Private' ;;
    ProofPrefix) constants='Mutation = "none"'; invariants='ExactPrefix GroundedPrefix PublishedGrounded RefusalPrivate PublicationPhase' ;;
    ProofShapeAdmission) constants='Mutation = "none"'; invariants='AllocationAfterAdmission AdmittedShape RefusalUnpublished PublicationAfterIndex' ;;
    TerminalTraversal) constants='Mutation = "none"'; invariants='Bounds FailureFrozen CompletedScan' ;;
    CertificateMaterial) constants='Mutation = "none"'; invariants='CountExact UsageBounds ReservedBeforeCopy NoPartialPublication FailureTerminal' ;;
    NegativeProbe) constants='Mutation = "none"'; invariants='AbsenceSound WitnessSound FailureTerminal Bounds' ;;
    NumericProbe) constants='Mutation = "none"'; invariants='TypedPrefix PrefixValue PublicationExact Unpublished Bounds' ;;
    CountProbe) constants='Mutation = "none"'; invariants='PrefixCount CompleteExact PublishedOnlyComplete FailureTerminal Bounds' ;;
    OwnedLookup) constants='Mutation = "none"'; invariants='FrozenExact OrderedExact RejectedStable' ;;
    WeightedExport) constants='Mutation = "none"'; invariants='FrozenExact OrderedExact IndependentReads AxisExact CountExact SharedPlanExact MembershipExact DifferenceExact GroupedQueryExact FrozenPlanExact CompleteKeyExact TinyOwnerExact RoutedPointExact PointMemberExact' ;;
    RectangleCompaction) constants='Mutation = "none"'; invariants='OrderedExact WeightedCount IndependentReaders' ;;
    RectangleExport) constants='Mutation = "none"'; invariants='FrozenExact OrderedExact IndependentReads CountExact' ;;
    ProviderViews) constants="Rows = {0,1,2}\nBudget = 2\nMutation = \"none\"\nExplorationBound = $views_cutoff"; invariants='AtomicPublication FrozenRead ReaderAlive CurrentReply LogicalBudget'; constraint=Explore ;;
    ReaderLifetime) constants='Rows = {0,1,2}\nReaders = {1,2}\nBudget = 2\nMutation = "none"'; invariants='ReaderAlive AcceptedCurrent CreditBalance'; properties=ReaderCompletion; specification=spec ;;
    ReadyComponents) constants='Tasks = {1,2,3}\nCapacity = 2\nMutation = "none"'; invariants='Partition Prerequisites CapacityBound CompleteReturn DependencySnapshot CompletedDelivery' ;;
    TransitiveComponents) constants='Nodes = {1,2,3}\nMutation = "none"'; invariants='ReachExact SCCExact ParentRoots PrivateArcs RefusalAtomic ActiveExact DeltaExact ParentChains MemberPartition SizeExact WeightedDeltaExact DifferenceExact ExcessWeightExact SparseMassExact' ;;
  esac
  base="$temp/$model.cfg"
  if [[ -n "$specification" ]]; then printf 'SPECIFICATION %s\n' "$specification" > "$base"; else printf 'INIT q_init\nNEXT q_step\n' > "$base"; fi
  configured_invariants=
  for property in $invariants; do
    if [[ "$main" != "$model" ]]; then property="${main}_${model}_$property"; fi
    configured_invariants+=" $property"
  done
  printf 'CONSTANTS\n%b\nINVARIANTS %s\nCHECK_DEADLOCK FALSE\n' "$constants" "$configured_invariants" >> "$base"
  if [[ -n "$properties" ]]; then printf 'PROPERTIES %s\n' "$properties" >> "$base"; fi
  if [[ -n "$constraint" ]]; then printf 'CONSTRAINT %s\n' "$constraint" >> "$base"; fi
}
cache=.cache/ascent/quint-compiled
mkdir -p "$cache"
backend_hash=$(shasum -a 256 "$jar" | awk '{print $1}')
port=$((20000 + $$ % 30000))
start_compiler() {
  java -Xmx1G -Xss32m -XX:+UseParallelGC "-Djava.io.tmpdir=$temp" -jar "$jar" server "--port=$port" > "$temp/server.out" 2>&1 &
  server_pid=$!
  ready=0
  for ((attempt=0; attempt<30; attempt++)); do
    if node - "$port" <<'JS'
const grpc = require('./.cache/ascent/tools/quint/node_modules/@grpc/grpc-js');
const loader = require('./.cache/ascent/tools/quint/node_modules/@grpc/proto-loader');
const proto = grpc.loadPackageDefinition(loader.loadSync('./.cache/ascent/tools/quint/node_modules/@informalsystems/quint/dist/src/reflection.proto', {keepCase:true}));
const client = new proto.grpc.reflection.v1alpha.ServerReflection('127.0.0.1:'+process.argv[2], grpc.credentials.createInsecure());
const call = client.ServerReflectionInfo({deadline:new Date(Date.now()+1000)});
call.on('data', r => {client.close(); process.exit(r.file_descriptor_response ? 0 : 1)});
call.on('error', () => {client.close(); process.exit(1)});
call.write({file_containing_symbol:'shai.cmdExecutor.CmdExecutor'});
JS
    then ready=1; break; fi
    kill -0 "$server_pid" 2>/dev/null || break
    sleep 1
  done
  if [[ "$ready" != 1 ]]; then cat "$temp/server.out" >&2; exit 1; fi
}
for model in "${models[@]}"; do
  configure
  source="packages/proofs/quint/$model.qnt"
  temporal="$properties"
  if [[ "$model" = ReaderLifetime ]]; then temporal='ReaderCompletion RoundCompletion spec roundSpec'; fi
  fingerprint=$({ cat "$source" packages/proofs/quint/package-lock.json; printf '%s\n' "$backend_hash" "$main" "$invariants" "$temporal" "$constraint"; } | shasum -a 256 | awk '{print $1}')
  hit=0
  if [[ -f "$cache/$model.identity" && -f "$cache/$model.tla" ]]; then
    read -r expected artifact_hash < "$cache/$model.identity"
    actual=$(shasum -a 256 "$cache/$model.tla" | awk '{print $1}')
    if [[ "$expected" = "$fingerprint" && "$artifact_hash" = "$actual" ]]; then hit=1; fi
  fi
  if [[ "$hit" = 1 ]]; then cp "$cache/$model.tla" "$temp/$main.tla"; else
    if [[ -z "$server_pid" ]]; then start_compiler; fi
    compile_invariants="$invariants${constraint:+ $constraint}"
    options=(--main "$main" --target tlaplus --init init --step step --invariant "${compile_invariants// /,}" --apalache-version 0.62.1 --server-endpoint "127.0.0.1:$port" --verbosity 0)
    if [[ -n "$temporal" ]]; then options+=(--temporal "${temporal// /,}"); fi
    "$quint" compile "$source" "${options[@]}" > "$temp/$main.tla"
    grep -q "MODULE $main " "$temp/$main.tla"
    cp "$temp/$main.tla" "$cache/$model.tla"
    artifact_hash=$(shasum -a 256 "$cache/$model.tla" | awk '{print $1}')
    printf '%s %s\n' "$fingerprint" "$artifact_hash" > "$cache/$model.identity"
  fi
  # Apalache defines assignment annotations as equality. TLC's ENABLED
  # handling of the annotated call can spuriously disable fair actions.
  # Erase only operator tokens, preserving all quoted model values.
  node - "$temp/$main.tla" <<'JS'
const fs = require('fs');
const path = process.argv[2];
const source = fs.readFileSync(path, 'utf8');
fs.writeFileSync(path, source.replace(/"(?:\\.|[^"\\])*"|:=/g, token => token === ':=' ? '=' : token));
JS
  echo "QUINT-COMPILE-OK $model cache=$hit"
    done
    if [[ -n "$server_pid" ]]; then kill "$server_pid"; wait "$server_pid" || true; server_pid=; fi
    check_model() {
      local model="$1" main base specification constraint properties constants invariants variant code expected property mutation capacity
      configure
      execute() {
        local variant="$1" config="$2" expected="$3" property="${4:-}" code=0
        java -Xmx1G -XX:+UseParallelGC "-Djava.io.tmpdir=$temp/$model" -cp "$jar" tlc2.TLC -workers 1 -config "$config" -metadir "$temp/$model/$variant" "$temp/$main.tla" 2>&1 | tee "$temp/$model-$variant.out" | awk -v label="$model-$variant" '/^Progress\(/ {print label ": " $0; fflush()}' || code=$?
        if [[ "$code" != "$expected" ]]; then cat "$temp/$model-$variant.out" >&2; echo "Quint checker failure: $model $variant exit=$code expected=$expected" >&2; return 1; fi
        if [[ "$expected" = 0 ]]; then
          grep -q 'Model checking completed. No error has been found.' "$temp/$model-$variant.out"
          grep 'states generated.*distinct states found' "$temp/$model-$variant.out" | tail -1
          echo "QUINT-CHECK-OK $model $variant"
        elif [[ "$expected" = 12 ]]; then
          grep -q "Invariant $property is violated" "$temp/$model-$variant.out" || { cat "$temp/$model-$variant.out" >&2; return 1; }
          echo "COUNTEREXAMPLE-OK $model-$variant $property exit=12"
        else
          grep -Eq "Temporal propert(y $property was|ies were) violated|Action property $property is violated" "$temp/$model-$variant.out" || { cat "$temp/$model-$variant.out" >&2; return 1; }
          echo "COUNTEREXAMPLE-OK $model-$variant $property exit=13"
        fi
      }
      fault() {
        mutation="$1"; property="$2"; expected="${3:-12}"
        if [[ "$main" != "$model" ]]; then property="${main}_${model}_$property"; fi
        variant="$temp/$model-$mutation.cfg"
        sed -e "s/Mutation = \"none\"/Mutation = \"$mutation\"/" -e "s/Fault = \"none\"/Fault = \"$mutation\"/" -e 's/EarlyReturn = FALSE/EarlyReturn = TRUE/' -e '/^INVARIANTS /d' -e '/^PROPERTIES /d' "$base" > "$variant"
        if [[ "$expected" = 12 ]]; then printf 'INVARIANT %s\n' "$property" >> "$variant"; else printf 'PROPERTY %s\n' "$property" >> "$variant"; fi
        if [[ "$model" = ProviderFrontier && "$mutation" = initial ]]; then sed -i.bak 's/Seeded = FALSE/Seeded = TRUE/' "$variant"; fi
        if [[ "$model" = LatticeProjection && "$mutation" = budget-skip || "$model" = LatticeProjection && "$mutation" = budget-events || "$model" = LatticeProjection && "$mutation" = refusal-publish ]]; then sed -i.bak 's/Remaining = 2/Remaining = 1/' "$variant"; fi
        execute "$mutation" "$variant" "$expected" "$property"
      }
      mkdir -p "$temp/$model"
      execute correct "$base" 0
      case "$model" in
        ActorRound) fault early CompletePublication; fault stale NoStaleCompletion; fault cancel CompletePublication ;;
        ActorRoundCredits|ActorTestPool) for capacity in 1 3; do sed "s/Capacity = 2/Capacity = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "capacity-$capacity" "$temp/$model-capacity.cfg" 0; done; fault early CompleteReturn ;;
        ActorSession) fault stale NoStalePublication; fault early DrainedClose ;;
        ComponentIndex) for mutation in order early failed alias foreign reset columns rebuild-columns; do fault "$mutation" Consistent; done; fault held HeldStable; fault held-columns HeldStable; for mutation in extend-view failed-view rebuild-view; do fault "$mutation" ViewConsistent; done ;;
        LatticeProjection) for capacity in 0 1; do sed "s/Remaining = 2/Remaining = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "remaining-$capacity" "$temp/$model-capacity.cfg" 0; done; for mutation in overwrite prior false; do fault "$mutation" MapExact; done; for mutation in retain early stale; do fault "$mutation" SnapshotExact; done; fault borrow HeldStable; fault lost-key KeyCoverage; fault repeat-key KeyCoverage; fault budget-skip BudgetBound; fault budget-events RefusalSound; fault refusal-publish RefusalStable ;;
        NativeSessionPublication) for mutation in early bounded alias; do fault "$mutation" CommittedSnapshot; done ;;
        NativeEvidenceLifecycle) sed 's/InputLimit = 0/InputLimit = 1/' "$base" > "$temp/$model-finite.cfg"; execute caller-finite "$temp/$model-finite.cfg" 0; fault stale CurrentResult; fault coupled IndependentExplanation; fault rewrite FrozenObservation; fault reject RejectionAtomic; fault close ClosedOwners ;;
        NativeDslOwnership) fault scope IsolatedDefinitions; fault failed ChargedExpansion; fault reset ChargedExpansion; fault foreign NoForeignReference ;;
        EvidenceCacheAdmission) fault source ExactSource; fault backend ExactBackend; fault policy ExactPolicy; fault retain FailureRevoked ;;
        SessionTransaction) fault early AtomicSnapshot; fault stale NoStaleCommit 13; fault global AtomicSnapshot; fault reuse AtomicSnapshot ;;
        ProviderFrontier) sed 's/Seeded = FALSE/Seeded = TRUE/' "$base" > "$temp/seeded.cfg"; execute seeded "$temp/seeded.cfg" 0; sed 's/Fault = "none"/Fault = "overlap"/' "$base" > "$temp/overlap.cfg"; execute overlap "$temp/overlap.cfg" 0; fault raw FrontierComplete; fault foreign FrontierComplete; fault omit DeliveredExact; for mutation in early old initial replace; do fault "$mutation" ConsumerSnapshot; done ;;
        ProviderReplay) fault scope PublishedExact; fault early JournalExact; fault drop JournalExact; fault kind OrderExact; fault cut HeldExact; fault reject RefusalAtomic ;;
        ProviderAdmission) fault nocap MatchingExact; fault set MatchingExact; fault allwitness CountCaps; fault early NoEarlyCallbacks; fault borrow DetachedPacket; fault retain FailedCacheRevoked ;;
        ProviderRouting) for mutation in drop order representative prefix; do fault "$mutation" CompleteExact; done ;;
        OwnedLookup) fault export OrderedExact; fault order OrderedExact; fault empty OrderedExact; fault duplicate OrderedExact; fault shared OrderedExact; fault borrow FrozenExact; fault retire FrozenExact; fault reject RejectedStable ;;
        WeightedExport) fault point-head-drop PointMemberExact; fault tiny-owner TinyOwnerExact; fault point-drop RoutedPointExact; fault point-prefix CompleteKeyExact; fault point-owner CompleteKeyExact; fault merge-skip FrozenPlanExact; fault merge-order FrozenPlanExact; fault repeat-conflict GroupedQueryExact; fault group-owner GroupedQueryExact; fault owner-cross MembershipExact; fault member-miss MembershipExact; fault selected-order AxisExact; fault plan-axis SharedPlanExact; fault order OrderedExact; fault alias FrozenExact; fault shared IndependentReads; fault axis AxisExact; fault mass CountExact ;;
        RectangleCompaction) fault heavy OrderedExact; fault order OrderedExact; fault alias OrderedExact; fault mass WeightedCount; fault shared IndependentReaders ;;
        RectangleExport) fault order OrderedExact; fault alias FrozenExact; fault shared IndependentReads ;;
        ProviderViews) fault alias FrozenRead; fault retire ReaderAlive; fault early AtomicPublication; fault stale CurrentReply; fault budget LogicalBudget ;;
        ReaderLifetime) for mutation in stuck unfair global; do fault "$mutation" ReaderCompletion 13; done; fault retire ReaderAlive; fault credit CreditBalance; fault aba AcceptedCurrent;
          sed -e 's/Readers = {1,2}/Readers = {1}/' -e 's/Mutation = "none"/Mutation = "global"/' "$base" > "$temp/single.cfg"; execute single-reader-global-fairness "$temp/single.cfg" 0;
          sed -e 's/SPECIFICATION spec/SPECIFICATION roundSpec/' -e 's/PROPERTIES ReaderCompletion/PROPERTIES ReaderCompletion RoundCompletion/' "$base" > "$temp/round.cfg"; execute sealed-round "$temp/round.cfg" 0;
          sed -e 's/Mutation = "none"/Mutation = "unfair"/' -e '/^INVARIANTS /d' -e '/^PROPERTIES /d' "$temp/round.cfg" > "$temp/round-unfair.cfg"; printf 'PROPERTY RoundCompletion\n' >> "$temp/round-unfair.cfg"; execute sealed-round-unfair "$temp/round-unfair.cfg" 13 RoundCompletion ;;
        ReadyComponents) for capacity in 1 3; do sed "s/Capacity = 2/Capacity = $capacity/" "$base" > "$temp/$model-capacity.cfg"; execute "capacity-$capacity" "$temp/$model-capacity.cfg" 0; done; fault prerequisite Prerequisites; fault early CompleteReturn; fault snapshot DependencySnapshot; fault tail CompletedDelivery; fault credit CompletedDelivery ;;
        TransitiveComponents) fault split SCCExact; fault stale ReachExact; fault reject RefusalAtomic; for mutation in raw diagonal old; do fault "$mutation" DeltaExact; done; fault chain ParentChains; fault members MemberPartition; fault size SizeExact; fault adjacency PrivateArcs; fault weight WeightedDeltaExact; fault excess ExcessWeightExact; fault sparseSelf SparseMassExact ;;
        OracleTransport) fault early CompleteReaders; fault swallow ReaderClean; fault tail CompleteBytes; fault interrupt ReaderErrorSound ;;
        WithdrawalSession) fault early AtomicSnapshot; fault graphEdit FrozenGraph; fault unchecked AtomicSnapshot; fault ordinal CurrentOrdinal; fault forgetRemoved CumulativeSupport; fault rebase CurrentTokens; fault borrowObservation HistoricalObservation; fault compactLoss SupportCoverage; fault compactEarly StorageAtomic; fault compactRebase CurrentTokens; fault uncharged BudgetAdmission ;;
        MinimumHeight) fault first CompleteMinimum; fault stale CompleteMinimum; fault early Private; fault cycle CompleteMinimum; fault minimumBody CompleteMinimum ;;
        WithdrawalConcurrency) fault outside OnePublicationPerGeneration; fault abandon TerminalReleased; fault earlyUnlock ExclusiveOwnership; sed 's/SecondExpected = 0/SecondExpected = 1/' "$base" > "$temp/$model-successor.cfg"; execute successor "$temp/$model-successor.cfg" 0; sed 's/Mutation = "none"/Mutation = "lateReceipt"/' "$temp/$model-successor.cfg" > "$temp/$model-late.cfg"; execute late-receipt "$temp/$model-late.cfg" 12 ReceiptBound ;;
        ChangePlan) fault alias Frozen; fault borrow Frozen; fault early CompletePublication; fault failure FailureAtomic ;;
        DerivationCounts) fault refusal Private; fault early Fixed; fault accumulate Fixed ;;
        CanonicalIndex) fault early Private; fault omit Canonical; fault duplicate Canonical; fault order Canonical ;;
        Withholding) fault early Private; fault local Protected; fault stale Bound; fault missing Protected ;;
        ExecutionFeedback) fault stale Qualified; fault partial Qualified; fault missing ExactDifferences; fault extra ExactDifferences; fault referenceStale Qualified; fault referencePartial Qualified; fault query Qualified ;;
        ScopedReachabilityMask) fault global ExactWitnesses; fault late ExactWitnesses; fault cleanAlternative ExactBranches; fault forgetWitness ExactWitnesses ;;
        MovieCastQuery) fault global ExactEvidence; fault early ExactEvidence; fault union ExactAnswer; fault forget ExactTrace ;;
        ScopedQuery) fault unbounded ExactHops; fault independentSides ExactWitnesses; fault global ExactWitnesses; fault forgetPredecessor ExactPredecessors; fault forgetTrace ExactTraces ;;
        ScopedComposition) fault union ExactAnswer; fault allBranches ExactCoverage; fault emptyGroup ExactMissing; fault forgetWitness ExactWitnesses ;;
        BranchScopedWitness) fault crossMask ExactWitnesses; fault switchMask ExactWitnesses; fault forgetScope ExactWitnesses; fault collapseBranch ExactBranches ;;
        ScopedWitness) fault late ExactWitnesses; fault global ExactAnswer; fault anyBlocked ExactWitnesses; fault forget ExactWitnesses ;;
        ProofPrefix) fault early ExactPrefix; fault forward GroundedPrefix; fault source GroundedPrefix; fault partial RefusalPrivate ;;
        ProofShapeAdmission) fault early AllocationAfterAdmission; fault roots AdmittedShape; fault improper AdmittedShape; fault partial RefusalUnpublished ;;
        TerminalTraversal) fault tail FailureFrozen; fault resume FailureFrozen; fault skip FailureFrozen; fault early CompletedScan ;;
        CertificateMaterial) fault seed-skip CountExact; fault late ReservedBeforeCopy; fault partial NoPartialPublication; fault resume FailureTerminal ;;
        NegativeProbe) fault early AbsenceSound; fault refusal AbsenceSound; fault resume FailureTerminal ;;
        NumericProbe) fault type-skip TypedPrefix; fault empty PrefixValue; fault zero PrefixValue; fault early PublicationExact; fault refusal Unpublished ;;
        CountProbe) fault unmatched PrefixCount; fault early CompleteExact; fault refusal PublishedOnlyComplete; fault resume FailureTerminal ;;
      esac
    }
    # Calls run as simple commands in independent subshells: failures terminate
    # their lane, and both child exit statuses are required by the parent.
    lane() { local offset="$1" i; for ((i=offset;i<${#models[@]};i+=2)); do check_model "${models[i]}"; done; }
    lane 0 & first=$!
    lane 1 & second=$!
    status=0
    wait "$first" || status=$?
    wait "$second" || status=$?
    [[ "$status" = 0 ]] || exit "$status"
    echo 'ALL-QUINT-CHECK-OK'
