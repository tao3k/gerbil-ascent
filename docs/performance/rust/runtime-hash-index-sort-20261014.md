# Rayon hash, index and publication optimization — 2026-10-14

Raw execution records are local artifacts under `.cache/ascent/rust-benchmarks/`, excluded from Git. Links to these records require the local archive; historical identities and failures are unchanged.

Historical measurements, not qualification of the current wheel. Referenced
`results-*` artifacts are local-only and deliberately excluded from Git.
These results do not establish current consumer performance closure.

Against the previous optimized executable, the final candidate reduces the median
in all 36 interleaved configurations by 25.2%–46.2%. It wins 241 of 252 individual
pairs; the other 11 pairs are retained. The two requested one-worker cases improve
28.0% and 31.3%, each with all seven pairs faster. This is local evidence from the
same six inputs, not a claim of universal speedup or linear scaling.

## Changes and semantic boundary

- Admission assigns dense index slots to clause atoms and stores index requirements
  in the compiled plan. Evaluation no longer reconstructs these requirements on
  every run, and probes no longer search a BTreeMap of column vectors. Single-column
  indexes borrow the bound/literal `Value` directly; composite keys retain SmallVec
  storage and normal spill behavior. Standard randomized hash maps remain in indexes.
- Each evaluation creates one `RandomState` digest authority. An internal immutable
  fact carries its complete typed row and its keyed digest through local dedup,
  pending admission and frontier membership. Private sets consume the cached digest
  instead of hashing the row repeatedly. Digest collisions still compare the full
  typed row. No digest persists across evaluations or enters the public API. This
  does not substitute an unkeyed fast hash or assume collision-free fingerprints.
  The unit test deliberately forces identical digests for distinct typed values.
- Completed fact sets strip their private digests directly into result vectors;
  digest wrapping adds no final row-rehash pass. Unique rows use `sort_unstable`, which preserves their
  exact lexicographic order. At 16,384 or more rows and more than one enabled worker,
  sorting uses the caller-owned pool's `par_sort_unstable`; short sorts, explicit
  serial controls and one-worker pools remain sequential. The cutoff is an overhead
  guard qualified on these workloads, not a generally optimal tuning result.

The fact digest adds eight bytes to each internal fact key before table overhead.
No heap-usage reduction or hard memory cap is claimed. Sources and public snapshots
retain owned typed values; no Scheme pointer, JSON transport or new public namespace
is introduced. Scheme still owns the generated matching/rule/round composition;
this bounded backend does not port every existing Scheme feature.

Work charging, per-candidate cancellation checks, exact checked fact counters,
per-relation pending locks and candidate-admission boundaries are unchanged. New
facts are charged before insertion into global pending sets. Failure restores
committed sources and preserves the previous completed snapshot. After all sorting,
publication performs a fresh cancel/deadline check; queued pool work and sorting
remain inside the session deadline. Limits remain cooperative, not a real-time
interrupt or process-level heap limit. Rust Ascent remains a **dev-dependency oracle**.

## The two historical one-worker regressions

The previous report retained a tiny-input regression (1.837 to 2.370 ms) and a large
single-component regression (214.550 to 226.396 ms). Its tiny after samples ranged
from 1.112 to 20.297 ms; before ranged from 1.132 to 4.092 ms. Most of that difference
was in `solve`, with some export variation; admission and replacement were tiny.
It was not evidence of a measured 29% increase in instruction cost.

Frozen original and previous executables were rerun with 21 timed operations after
one warmup per process, for both explicit serial and Rayon(1) controls. These are
stability diagnostics in fixed order, not randomized causal comparisons. The
historical tiny slowdown does not reproduce: original Rayon(1) is 1.090 ms and
previous Rayon(1) is 1.070 ms. The large case still shows a regression in this
fixed-order diagnostic: 193.523 to 210.433 ms (8.7% slower); serial is 181.580 to
208.476 ms. Its distributions and other protocols vary substantially. These
[168 diagnostic samples](../../../.cache/ascent/rust-benchmarks/results-hash-index-sort-20261014/diagnostic-repeats-summary.tsv)
do not identify a unique
scheduler/CPU-frequency cause; caller condition-variable waits alone cannot do so,
since the caller normally waits while its worker executes.

Steady-state sampling and the code do identify avoidable work: repeated typed-row
hashing across sets, cloned unary index keys, and sequential stable snapshot sorts.
The changes above remove that work without changing the one-worker execution policy.
The final interleaved comparison supports a reduction in current latency; it does
not retroactively prove that these costs caused every historical slow sample.

## Final interleaved control

Both frozen binaries use the unchanged harness, graph generator, limits and output
checks. Each of 36 configurations has seven alternating-order pairs, one warmup and
one timed operation per child: **504 timed samples**. Process/pool creation and
complete output validation are outside timing. `wall` includes admission, source
replacement, solve/publication and export. The previous executable is the immediate
baseline from the earlier optimization, not the initial implementation.

Selected medians in milliseconds; all configurations, phases, ranges and pair counts
are in [paired-final-summary.tsv](../../../.cache/ascent/rust-benchmarks/results-hash-index-sort-20261014/paired-final-summary.tsv).

| K / G / W | Workers | Previous | Final | Reduction | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 / 16 / 16 | 1 | 1.096 | 0.789 | 28.0% | 7/7 |
| 1 / 256 / 16 | 1 | 16.218 | 11.139 | 31.3% | 7/7 |
| 8 / 32 / 16 | 1 | 16.249 | 11.191 | 31.1% | 6/7 |
| 1 / 32 / 64 | 1 | 32.476 | 22.692 | 30.1% | 7/7 |
| 1 / 2048 / 16 | 1 | 183.215 | 125.800 | 31.3% | 7/7 |
| 8 / 256 / 16 | 1 | 150.587 | 111.617 | 25.9% | 7/7 |
| 1 / 2048 / 16 | 4 | 147.792 | 79.557 | 46.2% | 7/7 |
| 8 / 256 / 16 | 4 | 88.038 | 52.563 | 40.3% | 7/7 |

Two intermediate full paired matrices are also retained. Index slots, borrowed unary
keys and sequential unstable sorting alone improved 31/36 medians; five regressed,
including tiny Rayon(2) by 8.9%. Adding digest reuse and the direct row-vector handoff improved
36/36 medians in its own run. These successive runs have different host histories;
subtracting their percentages does not isolate each change's causal contribution.

## Same continuous-process matrix

The unchanged six K/G/W shapes use 1/2/4/8/12 Actor capacities in one Scheme VM;
serial and 1/2/4/8/12 Rayon workers; and Rust Ascent solely as an independent oracle.
One warmup and seven retained operations per configuration give **504 timed samples,
72 configurations**. Every completed sample checks the exact closure. K means
independent rule components, G chains per component, W nodes per chain.

| K / G / W | Actor(1) | Serial | Rayon 1 | Rayon 2 | Rayon 4 | Rayon 8 | Rayon 12 | Rust oracle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 / 16 / 16 | 10.297 | 0.772 | 0.767 | 0.750 | 0.774 | 0.781 | 0.780 | 0.166 |
| 1 / 256 / 16 | 96.457 | 13.385 | 12.071 | 12.713 | 9.257 | 10.814 | 11.597 | 2.874 |
| 8 / 32 / 16 | 107.024 | 11.930 | 11.026 | 8.232 | 8.536 | 7.745 | 8.484 | 2.657 |
| 1 / 32 / 64 | 404.632 | 23.753 | 23.088 | 17.869 | 15.334 | 23.617 | 27.049 | 5.432 |
| 1 / 2048 / 16 | 787.200 | 134.036 | 124.448 | 99.405 | 89.915 | 82.295 | 84.820 | 24.173 |
| 8 / 256 / 16 | 688.422 | 106.396 | 107.305 | 77.951 | 53.823 | 55.497 | 57.734 | 23.565 |

The large eight-component case reaches 1.99× at four workers versus Rayon(1);
the large single-component case reaches 1.51× at eight. Higher counts can lose:
Rayon(12) on the longer-chain case takes 27.049 ms versus 23.088 ms at one worker.
All logical Actor capacities and timing ranges remain in
[matrix-summary.tsv](../../../.cache/ascent/rust-benchmarks/results-hash-index-sort-20261014/matrix-summary.tsv).
Do not combine medians across this protocol and the short-lived paired children.
The bounded generated backend and existing Scheme evaluator have different storage
and admission kernels, so their absolute latency ratio is not a pure scheduler gain.

## Actual multi-VM Actor control

The unchanged Darwin diagnostic was rerun for all six inputs, 1/2/4/8/12 distinct VM
images and seven operations each: **210 samples, 30 successful processes**. Each VM
has one OS-thread owner and runs the existing Scheme Actor evaluator. Owner receipts
verify distinct states, synchronized entry, exact partitioned results and cleanup.
This is the same independent-chain partitioning control described in the
[previous report](runtime-optimization-20261014.md), not a production VM executor or
shared-VM multithreading/GC fix. Copy/setup/cleanup costs remain outside steady timing;
the VM operation includes Actor closure, unlike the primary Actor span.

| K / G / W | VM 1 | VM 2 | VM 4 | VM 8 | VM 12 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 / 2048 / 16 | 896.68 | 438.62 | 219.19 | 144.31 | 128.40 |
| 8 / 256 / 16 | 725.76 | 396.46 | 222.57 | 162.53 | 177.88 |

All six shapes and every sample are retained in
[multivm-summary.tsv](../../../.cache/ascent/rust-benchmarks/results-hash-index-sort-20261014/multivm-summary.tsv).
Single-component large scaling is 6.98× at twelve VMs; eight-component large scaling
is 4.47× at eight VMs, with twelve regressing. This does not generalize to programs
that require communication between VM partitions.

## Remaining hotspots and profiling limits

Own-process `sample` captures use a one-second warmup before five seconds of
1 ms sampling, separately from every benchmark matrix. Frozen original, previous
and final binaries were sampled on both requested one-worker inputs. The final
large eight-component case was additionally sampled with four workers. All seven
captures completed successfully; full stacks and their run transcripts remain in
`.cache/ascent/rayon-followup-20261014/`, with collapsed leaf stacks in the receipts.

Large single-component Rayon(1) leaf observations:

| Frame family | Original | Previous | Final |
| --- | ---: | ---: | ---: |
| Clock (`mach_absolute_time`) | 1,183 | 19 | 36 |
| SipHash/default-hasher writes | 352 | 957 | 185 |
| Snapshot slice-sort frames | 239 | 376 | 327 |

These are sampled leaf observations in separate five-second windows, not CPU
percentages, query-normalized costs or allocation counts. Faster binaries execute
more queries during a window. Symbol inlining differs, so frame-count subtraction
is not a causal decomposition. Caller condition-variable waits are expected pool
handoffs and include idle time; they must not be called useful CPU work or a proven
scheduler bottleneck.

The final one-worker large capture still exposes hash-table insertion (405 leaf
observations), binding (386), value comparison (310) and index probes (177). The
four-worker large K=8 capture has table insertion (660), binding (623), binding-slot
construction/update (403/462), index probes (336), slice sorts (677) and Rayon sort
recursion (390). Randomized hashing is now a much smaller visible hotspot; bucket
insertion/growth, binding copies, typed comparisons and ordered frontier publication
still cost work. More workers cannot eliminate these costs, and this implementation
still projects each rule's completed binding batch and publishes its frontier under
one owner. No lock-free admission or relaxation of limits was introduced to hide
that boundary.

Two early non-steady captures remain in the cache but are excluded from this table.
An initial repeat batch that may have overlapped our own profiling is retained as
`diagnostic-repeats-initial-uncontrolled.json` and excluded from qualified counts;
it was replaced with the sequential 168-sample diagnostic above. Negative samples
and intermediate regressions were not dropped.

## Qualification and receipts

- Default and `--no-default-features`: **18 tests pass each**, including the actual
  ASP dev-dependency gates, chunk-edge exact work/fact admission, duplicate rules,
  all-relation fact caps, cancellation/deadline rollback, wide spill keys, Scheme
  parity and generated-graph Rust Ascent alignment. New tests force digest collisions,
  exercise several index shapes on one typed relation with reversed/duplicate input,
  and check exact sorted publication above the parallel-sort cutoff.
- Workspace Clippy `--all-targets -- -D warnings` passes in both feature modes;
  workspace formatting passes. Normal core dependencies remain Rayon and SmallVec,
  with no Rust Ascent evaluator or Scheme VM dependency.
- The release Maturin/PyO3 wheel is rebuilt and its installed integration suite
  checks owned typed conversion, immutable/rollback semantics and parallel callers.
  Detailed logs and exit status receipts accompany the measurements.
- No remote CI, commit, push or production VM qualification is claimed.

The qualified timing receipts contain **2,394 samples**: three full paired matrices
(1,512), the final continuous matrix (504), actual multi-VM controls (210), and the
sequential stability diagnostic (168). Profiling operations and the uncontrolled
repeat batch are additional retained diagnostics, excluded from this denominator.
All 1,218 final paired/matrix/multi-VM samples completed and matched exact results.

Frozen immediate baseline SHA-256:
`c2312debf6c7800e73f45866d91b38229bcdb04e68128b3ec15e53b4096b7b13`.
Final measured executable SHA-256:
`c63a5bb540a75c7fd1595242f0e9bbc19e65598936fd5543a3889f986bb1c55a`.
The original pre-optimization and two intermediate binaries are separately retained.
[manifest.json](../../../.cache/ascent/rust-benchmarks/results-hash-index-sort-20261014/manifest.json) records binary,
source and harness identities, platform, qualification logs and evidence boundaries.
The checkout remains on `feature/ascent-scheme-syntax` at baseline `f53a9a3`, with
these support files uncommitted. The unchanged harness and nonisolated host remain
material limits on all timing claims.
