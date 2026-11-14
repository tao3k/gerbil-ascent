# ASCENT C ABI + AOT final qualification — 2026-10-15

Raw execution records are local artifacts under `.cache/ascent/rust-benchmarks/`, excluded from Git. The local links below do not make those artifacts part of a checkout or a published qualification bundle. Their original bytes, hashes and failed attempts are preserved.

The complete public interface now uses original Scheme ASCENT through pinned gerbil-scheme-rust. The general Rust Scheme evaluator was removed. Modules, components, closures, complex values, Value.apply, lattice operations, provenance and explanations use the original native semantics. Rust owns typed data, finite Rayon evaluation, control admission and PyO3. Downstream users load original Scheme DSL without invoking a compiler; library construction supplies AOT artifacts. Programs and results do not travel through JSON.

This qualifies the local working tree based on 98f488964e6bc0ec49167c3fc7075e1d05e78637, including subsequent uncommitted changes bound by the manifest. It is not remote CI or cross-platform qualification. The earlier report and matrices remain historical receipts for earlier executable bytes.

Publication scope: the local formal run also consumed concurrent RayonPublication
models and their Lean/Quint registrations. Those changes belong to another task
and are deliberately excluded from this publication. The recorded local model
counts and input hashes remain historical working-tree evidence, not a claim
that all those inputs exist in the published commit. Exact-commit CI separately
qualifies the committed model inventory and rebuilt runtime artifacts.

## Full semantic gates

| Gate | Result |
| --- | --- |
| Original Scheme | 169 modules / 1,349 cases; final OK and exit 0 |
| Workspace Rust, all features | 98 passed, zero failed or ignored |
| Strict Clippy and ASP repository policy | Passed, warnings denied |
| Original Python public semantics | 34 files / 193 cases, every declared outcome ok |
| Installed PyO3 package | 15 passed |
| Workbench | 149 passed |
| Installed native consumer matrix | 34/34 groups, 13.60s / unchanged 120s budget; 20,350 inputs, zero drift |
| Rust Ascent alignment | 79 regular cases + original ignored scale case explicitly run and passed |
| Lean controls | 163 build jobs passed |
| Quint controls | 52 models; 66 correct checks + 270 expected counterexamples passed |

Final runtime changes were followed by full Rust, installed-wheel, consumer and Python semantic runs. Original Scheme passed after the owner-admission fix; subsequent build-metadata changes do not alter Scheme evaluation. The unchanged differential and formal inputs retain their preceding controls. All 336 Quint obligations executed using source-bound cached compilations. These finite models do not prove arbitrary Scheme programs or the C ABI.

Cancellation is checked while waiting for the owner mutex, during native evaluation and during finite execution. Waiting and execution share one deadline, including cached answers. Python releases the GIL during owner waits so another thread can cancel. Three new Rust tests exercise cancellation, timeout and an already-expired idle-owner admission. Resource limits remain fail-closed; interrupted replacement retains the last committed generation. Original duplicate source occurrences remain distinct, and derived rows retain set semantics. Provenance version 3 verifies native result multiplicity, source identity, generation and current source-content digest, including external mutation. Unsupported host callbacks never produce a positive checked proof.

The original mutable typed-source getter contract was restored after the full corpus exposed an incorrect defensive copy. New compilation revalidates mutations; old published results remain owned. Build-frozen source identity now emits Cargo invalidation directives for the exact source directories and manifests it hashes; actual Cargo output was checked. Historical failures and raw final logs are retained in the [semantic receipts](../tests/qualification-20261015-final/summary.json).

## Same-data performance matrix

Apple M2 Pro, 12 physical/logical cores, 32 GiB RAM. Prebuilt dev-profile executable, optimization level 2 with debug/overflow checks. K is independent components, G chains per component, W chain width. Inputs contain K*G*(W-1) rows; outputs contain K*G*W*(W-1)/2 rows. Each of 36 configurations has one excluded warmup and seven measured samples; every tuple is validated in Rust.

The values below are median replace + execute + export wall time in milliseconds. VM replacement eagerly solves, so measuring its cached run alone would be invalid. Startup, DSL loading and teardown are outside the steady-state interval. The VM path has one VM owner thread. The Rayon path uses the same frontend VM and transfers finite owned data to 1/2/4/8/12 workers. This does not qualify multiple-VM throughput or a wholly VM-free frontend.

| K/G/W | VM 1 | Rayon 1 | Rayon 2 | Rayon 4 | Rayon 8 | Rayon 12 | Best threads | VM / best | Rayon 1 / best |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1/16/16 | 9.254 | 0.878 | 0.910 | 0.948 | 0.901 | 0.896 | 1 | 10.54x | 1.00x |
| 1/256/16 | 140.706 | 16.364 | 15.271 | 12.857 | 13.219 | 14.910 | 4 | 10.94x | 1.27x |
| 8/32/16 | 139.672 | 15.761 | 13.447 | 11.735 | 13.010 | 12.897 | 4 | 11.90x | 1.34x |
| 1/32/64 | 274.245 | 36.761 | 29.900 | 25.680 | 27.993 | 31.631 | 4 | 10.68x | 1.43x |
| 1/2048/16 | 1090.836 | 187.876 | 144.454 | 114.380 | 104.502 | 110.504 | 8 | 10.44x | 1.80x |
| 8/256/16 | 1142.014 | 136.237 | 95.170 | 65.894 | 68.889 | 69.158 | 4 | 17.33x | 2.07x |

The VM ratio includes different execution representation and transfer costs; it is not pure parallel speedup. The final column isolates the observed gain within Rayon. More workers need not improve performance, and the best thread count is the observed minimum in this six-shape matrix, not a universal setting.

| K/G/W | Best threads | Replace ms | Execute ms | Export ms |
| --- | ---: | ---: | ---: | ---: |
| 1/16/16 | 1 | 0.003 | 0.871 | 0.005 |
| 1/256/16 | 4 | 0.050 | 10.617 | 2.081 |
| 8/32/16 | 4 | 0.036 | 11.182 | 0.543 |
| 1/32/64 | 4 | 0.032 | 21.452 | 3.837 |
| 1/2048/16 | 8 | 0.396 | 101.321 | 2.307 |
| 8/256/16 | 4 | 0.298 | 62.206 | 3.446 |

Phase medians need not sum to the wall median. Execution still combines binding, collections/indexing, sorting and publication. These measurements do not causally attribute individual allocator/hash costs or establish linear scaling. Rust Ascent remains a dev-dependency semantic alignment control, not the production implementation or a performance baseline.

## Isolation and evidence

The final run required 60 continuous seconds without compiler/checker activity, then sampled host processes every half second throughout measurement. All owned builds/tests had exited. With explicit user authorization, three other chats temporarily deferred new heavy tasks while their existing validation processes completed naturally. Measurement observed zero compiler/checker interference and zero source-input drift. This is process-audited one-host evidence, without CPU affinity or whole-machine activity guarantees.

Two complete final-code matrices were rejected solely because compiler/checker interference was observed. They remain [first rejected final attempt](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final-interference/acceptance.json) and [second rejected final attempt](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final-interference-2/acceptance.json). Earlier executable matrices also remain untouched. No samples were discarded based on timing values.

Other retained failures include the unchanged 120s cold preparation timeout, the original typed-source mutation regression, split unittest output from a fork warning, an Apple linker Bus error, and ASP style failures. The source/parser/style defects were repaired; the linker retry used one build job. Assertions, runtime cancellation/limits, original timeouts and missing-outcome rejection were not weakened. Cold-build performance was not qualified.

- [252 raw measurements](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/samples.tsv)
- [36 commands, exits and sample counts](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/runs.json)
- [Source map, upstream revision and binary SHA](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/manifest.json)
- [Process audit](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/process-audit.json), [source audit](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/source-audit.json), [acceptance](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/acceptance.json)
- [Isolation driver](../../../.cache/ascent/rust-benchmarks/results-hybrid-20261015-final/isolation-driver.txt)
- [Semantic receipts, individual outcomes and wheel SHA](../tests/qualification-20261015-final/summary.json)

Rayon is the default feature. Rust Ascent and ASP Rust remain dev-dependencies. gerbil-scheme-rust is pinned to 2c82b845c141ce68147cf74cb5a4ec680c6ffb07. The upstream public runtime currently admits one VM per process with one owning OS thread. Arbitrary Scheme semantics execute there; unsupported forced finite projections fail explicitly. Matching Gerbil syntax resources are required at runtime: this wheel is not a standalone SDK, and its platform tag does not establish compatibility with older macOS releases.
