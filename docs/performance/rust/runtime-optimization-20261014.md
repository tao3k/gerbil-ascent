# Rayon optimization and real multi-VM Scheme measurement — 2026-10-14

Raw execution records are local artifacts under `.cache/ascent/rust-benchmarks/`, excluded from Git. Links to these records require the local archive; historical identities and failures are unchanged.

Historical measurements, not qualification of the current wheel. Referenced
`results-*` artifacts are local-only and deliberately excluded from Git.
These results do not establish current consumer performance closure.

The final Rayon implementation improves the four-worker median in all six
interleaved before/after comparisons, by 15.1%–39.4%. The larger eight-component
case improves 39.4% at four workers and 46.8% at twelve workers, with all seven
pairs faster. Single-worker regressions remain; this is not a claim that every
configuration improves. The normal dependency graph contains Rayon and SmallVec;
Rust Ascent remains **dev-only alignment**, not production evaluation.

The missing multi-VM measurement is now included: 1/2/4/8/12 dedicated OS owners
execute the existing Scheme Actor evaluator inside distinct, single-threaded
VM images in one process. The largest single-component, explicitly partitionable
input improves from 964.43 ms at one VM to 137.54 ms at twelve VMs (7.01×).
The eight-component large input improves from 765.37 ms to 175.57 ms at eight
VMs (4.36×); twelve VMs regress to 198.57 ms. Initialization is separate.

## Production changes and preserved contract

`execution/budget.rs` owns exact limits/cancellation; `execution/kernels.rs`
owns batching and storage; `execution/matching.rs` owns binding slots. The
Scheme function-IR producer remains the matching/rule/round composition owner.
This does not convert the entire existing Scheme evaluator into identical Rust
kernels; the implementation boundary documented in the initial report still
applies. Absolute Scheme/Rust timings are not pure scheduler speedups.

- Positive joins and projections charge the exact work needed by successful
  traversal, in groups of at most 128 units. Indexed single-row probes share a
  group across binding inputs instead of paying an atomic update and temporary
  vector per binding. Negative membership checks still charge only candidates
  actually visited before short-circuiting. Failed matches and duplicate
  projections still consume work. No unused worker credit is reserved.
- Work and fact counters use checked, bounded atomic updates. Admission cannot
  accept more than `max_states` or `max_facts`, including under concurrent
  relation shards; integer overflow cannot wrap a counter into admission.
- Deadline sampling occurs on charged-work batch crossings and source,
  admission, round, and final-publication boundaries. Cancellation flags remain
  checked on every matching/projection candidate. Timeouts remain cooperative;
  the accepted-result boundary still performs a fresh complete deadline/cancel
  check after deterministic snapshot construction. No late or partial snapshot
  can be published. This is not a new hard real-time latency guarantee.
- Projection filters the immutable committed frontier and deduplicates its
  current batch locally. Global candidate admission locks are **per relation**,
  and the global exact fact counter charges only accepted unique rows. Local
  dedup storage is cleared per batch. This keeps the global fact limit in
  candidate admission rather than deferring it until whole-round publication.
  Pending sets are cleared only after all tasks join and the owner updates the
  frontier. Fact accounting includes source facts and every relation.
- SmallVec stores up to four binding slots and two index-key values inline;
  wider cases spill normally. Unary/binary/nullary projections construct the
  immutable Arc row directly, avoiding an intermediate Vec allocation. The
  wider projection path remains supported. Delta insertion does not maintain a
  redundant membership set after the owner has already admitted a unique row.
- Session generation, source authority, rollback, immutable completed snapshots,
  deterministic result order, and unchanged-session reuse stay unchanged.
  No public `native` namespace, upstream Rust Ascent execution dependency,
  Python CFFI layer, or agent/context orchestration was added.

The first batched-admission candidate used one global mutex. Profiling exposed
that as a new hotspot, so it was replaced with per-relation locking before
final qualification. Its complete matrices and paired samples remain in the
receipts; it was not silently reported as the final implementation.

## Same workload matrix

The six K/G/W shapes, graph values, exact output checks, thread counts,
release/bench configuration, and timed phases are unchanged from the
[initial comparison](runtime-comparison-20261014.md). K is independent rule
components, G is chains per component, W is nodes per chain. Every sample
checks the complete exact closure, including the dev-dependency oracle.
Inputs, expected-row construction, compilation, process startup and validation
are outside the primary timed span. The Rust pool is reused across its seven
samples; fresh sessions prevent completed-result cache hits.

Final primary matrix: **504 timed samples, 72 configurations**, one warmup plus
seven retained samples each. Medians in milliseconds:

| K / G / W | Actor(1), one VM | Serial | Rayon 1 | Rayon 2 | Rayon 4 | Rayon 8 | Rayon 12 | Rust oracle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 / 16 / 16 | 10.57 | 1.15 | 1.15 | 1.43 | 1.62 | 1.51 | 1.44 | 0.17 |
| 1 / 256 / 16 | 98.89 | 19.68 | 18.83 | 15.88 | 32.13 | 16.68 | 17.07 | 3.03 |
| 8 / 32 / 16 | 110.17 | 18.20 | 18.57 | 13.87 | 13.43 | 12.89 | 12.59 | 2.71 |
| 1 / 32 / 64 | 428.44 | 34.80 | 34.43 | 29.77 | 31.44 | 35.32 | 40.36 | 5.71 |
| 1 / 2048 / 16 | 893.72 | 217.91 | 222.48 | 185.22 | 160.27 | 154.56 | 163.65 | 31.90 |
| 8 / 256 / 16 | 758.38 | 168.76 | 163.01 | 123.60 | 95.37 | 87.37 | 92.47 | 24.10 |

Actor worker counts 1/2/4/8/12 remain present in
[matrix-summary.tsv](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/matrix-summary.tsv), along
with every phase and min/max. These are logical Actor capacities inside one VM;
the separately measured multi-VM owners are below. The largest K=8/G=256/W=16
case reaches 1.87× parallel speedup at eight Rayon workers versus Rayon(1)
in this primary protocol; single-component large input reaches about 1.44×.
Neither is linear scaling. No automatic worker-count default was changed.

### Interleaved frozen-binary control

To avoid attributing host drift to code, the original executable was retained
before editing. Each old/new pair runs in alternating order, in separate
processes with one warmup and one timed operation each. There are **504 timed
samples = 36 configurations × 7 pairs × 2 versions**. These process-lifetime
and cache histories differ from the primary seven-sample process, so the
protocols are reported separately. Startup remains outside their timed spans.
All samples pass the executable's exact-output checks. The final lint-only
semicolon fix rebuilt to a byte-identical measured benchmark executable.

Four-worker results, medians in milliseconds:

| K / G / W | Before, Rayon 4 | After, Rayon 4 | Elapsed reduction | Faster pairs |
| --- | ---: | ---: | ---: | ---: |
| 1 / 16 / 16 | 1.60 | 1.21 | 24.3% | 7/7 |
| 1 / 256 / 16 | 20.77 | 15.31 | 26.3% | 7/7 |
| 8 / 32 / 16 | 17.67 | 12.01 | 32.1% | 6/7 |
| 1 / 32 / 64 | 44.42 | 32.23 | 27.4% | 6/7 |
| 1 / 2048 / 16 | 159.95 | 135.86 | 15.1% | 6/7 |
| 8 / 256 / 16 | 155.66 | 94.31 | 39.4% | 7/7 |

For the large eight-component case, Rayon(12) changes from 162.41 to 86.43 ms
(46.8% reduction, 7/7 faster pairs). Negative results remain: Rayon(1) regresses
29.0% on the smallest input in this process-per-pair protocol, and 5.5% on the
large single-component input. In the primary continuous-process matrix, the
medium single-component four-worker case regresses to 32.13 ms; its interleaved
comparison instead has seven faster pairs and a 15.31 ms final median. The
cause of that run sensitivity is not established. There is no affinity/load
isolation or statistically admitted universal improvement claim.

[paired-summary.tsv](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/paired-summary.tsv) retains
all worker counts, faster-pair denominators, medians and min/max ranges.

## Multi-VM flag and actual execution

The installed SDK already enables multiple VM storage and has a
single-threaded-VM ABI. The compiled diagnostic requires both capability bits;
each owner additionally checks that its active VM has one processor. Increasing
an Actor capacity or enabling multiple-VM storage alone does not bind the
ordinary foreign entry to independent VM state in this SDK. The pinned upstream
bridge documents that distinction and supplies a private-runtime-image
qualification design; this benchmark follows that diagnostic design.

The test loads a distinct image file for each dedicated pthread. Each image
contains the compiler-owned full ASCENT/Gerbil AOT graph and its own statically
linked Gambit state. `nm` exposes only the seven diagnostic adapter functions;
`otool` shows no shared Gambit/Gerbil runtime library. Other C libraries such as
OpenSSL remain shared. The same pinned `gerbil-scheme-aot-build` stages/builds
the graph; there is no SDK macro override, patched GC, alternate Gambit build,
or process-per-request substitution.

Every warmup and measured sample checks:

1. Distinct non-null Gambit global-state addresses for every owner.
2. One active processor per VM and a distinct Scheme marker checked after GC
   during preparation and again after every solve.
3. A callback barrier reached from inside Scheme on all owners: all distinct VM
   entry stacks overlap, not merely host requests waiting in a serial queue.
4. Every output tuple against the independent exact closure in its VM, and the
   host's complete expected union count across partitions.
5. Successful owner-affine cleanup and joining every owner after all samples.

The existing Actor evaluator runs with logical `workers: 1` inside each image.
The host explicitly partitions independent chain groups by
`(component*G + group) mod owner_count`. That is exact for this fixture: there
are no edges between chain groups. It does **not** establish correct partitioning
of an arbitrary recursive graph with cross-VM edges, or production multi-VM
admission, cancellation, hot switching, or safe image unload. Images remain
loaded until process exit; setup/cleanup are serialized because of process-wide
OS hooks. The provisional Gambit multi-threading/GC gap is not claimed repaired.

Multi-VM matrix: **210 timed samples, 30 configurations**, seven samples after
one warmup. Median complete fresh Actor session solve/export/close plus host
handoff/barriers, in milliseconds:

| K / G / W | VM 1 | VM 2 | VM 4 | VM 8 | VM 12 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 / 16 / 16 | 11.13 | 9.22 | 8.61 | 15.56 | 24.35 |
| 1 / 256 / 16 | 99.00 | 59.89 | 30.56 | 40.36 | 33.25 |
| 8 / 32 / 16 | 119.27 | 83.09 | 59.64 | 84.56 | 115.97 |
| 1 / 32 / 64 | 444.83 | 223.38 | 116.69 | 81.94 | 87.42 |
| 1 / 2048 / 16 | 964.43 | 477.99 | 251.23 | 166.33 | 137.54 |
| 8 / 256 / 16 | 765.37 | 431.95 | 235.98 | 175.57 | 198.57 |

Images, runtime setup, input/expected-row preparation and its GC occur before
steady timing. Exact validation happens after the timed response. Session
close/join is inside this VM timed operation, whereas the primary Actor table
stops before session close; these are not identical lifecycle spans.

Each image is 23.61 MB. Preparing all twelve image copies took 184.29 ms in this
run; copying is excluded from the steady table. For the large K=8 case, observed
startup/preparation took 41.90 ms for one owner and 141.27 ms for twelve;
teardown took 0.177 and 0.681 ms respectively. These are one observed lifecycle
span per configuration, not cold-start distributions. Peak memory and a fully
amortized production lifecycle comparison remain unqualified. All startup,
teardown, image identities, joins, ranges and ownership counts are retained in
[multi-VM receipts](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/multivm-summary.tsv).

## Profiling and checks

All profiling is excluded from latency tables. Matching five-second, 1 ms
sampling diagnostics of K=8/G=256/W=16 at Rayon(4) showed these collapsed
leaf-frame counts:

| Observed frame | Original | Intermediate global mutex | Final per-relation locks |
| --- | ---: | ---: | ---: |
| `mach_absolute_time` | 2220 | 83 | 75 |
| `__psynch_mutexwait` | 6 | 1324 | 12 |
| tiny allocations | 423 | 67 | 83 |
| allocator free | 355 | 76 | 103 |

These include samples across all threads, with sleeping/waiting frames and
inlining effects; they are not CPU/wall percentages or allocation counts.
Final hot stacks include hashing, binding, index lookup and deterministic
sorting. The time/allocator pressure decreased; the intermediate shared mutex
was a real measured tradeoff, and relation sharding removed it as a major
sampled hotspot in this workload. Remaining costs and serial publication are
not claimed eliminated.

Both default and `--no-default-features` configurations pass **15 Rust tests**
each, including the ASP gates, independent Scheme and Rust oracle alignment,
128-unit budget boundaries, duplicated rule outputs, global limits across
independent relation shards, wide binding/key spill, cancellation, timeout,
rollback and immutable snapshots. Workspace Clippy passes with `-D warnings`
in both configurations. Maturin rebuilt the wheel; all three installed-wheel
Python tests pass. Normal library dependencies are only Rayon and SmallVec;
Rust Ascent and ASP remain dev-dependencies. The diagnostic build tool also
passes release Clippy. This is local qualification, not remote CI closure.

## Receipts and reproduction

Final datasets contain **1,218 timed samples** (504 primary + 504 paired + 210
multi-VM). An additional **1,008 intermediate-candidate timed samples** remain
in this directory. Failed build/lint attempts were repaired before final
measurement; no final timed configuration failed or was dropped. The initial
report's four invalid retained-session controls remain in its earlier receipts.

- [Final raw matrix](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/matrix.tsv),
  [paired samples](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/paired.tsv),
  [multi-VM samples](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/multivm.tsv).
- [Source/binary identities](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/manifest.json),
  [final stacks](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/final-rayon4-top-stacks.txt),
  [intermediate stacks](../../../.cache/ascent/rust-benchmarks/results-optimization-20261014/intermediate-rayon4-top-stacks.txt).
- Run-status files and every multi-VM stderr lifecycle receipt are adjacent.
  Full profiling stacks and frozen binaries remain under `.cache/ascent`.

From the repository root, in the selected SDK environment:

```sh
cargo test --manifest-path rust/Cargo.toml --workspace --lib --tests --locked
cargo test --manifest-path rust/Cargo.toml --workspace --lib --tests \
  --no-default-features --locked
cargo bench --manifest-path rust/Cargo.toml -p gerbil-ascent \
  --bench runtime_comparison --no-run --locked
# Use the executable path printed by Cargo for --rust; run again with --large.
python3 -m ascent_workbench.benchmark_run_comparison \
  --scheme "$PWD/.cache/ascent/rust-rayon/scheme-runtime" \
  --rust "$PWD/rust/target/release/deps/runtime_comparison-<cargo-hash>" \
  --output "$PWD/.cache/ascent/runtime-comparison-new"
python3 -m ascent_workbench.benchmark_run_paired --before <frozen-original-executable> \
  --after <current-executable> --output <new-output-directory>
# Darwin-only diagnostic; Homebrew needs its OpenSSL pkg-config directory.
PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig" \
  cargo run --manifest-path rust/ascent-scheme/benches/support/vm-build/Cargo.toml --release --locked
python3 -m ascent_workbench.benchmark_run_multivm --output <new-output-directory>
```

The diagnostic tracks original core/program/table and adapter sources, not its
regenerated archive/image outputs. Gerbil `std/make` and the pinned upstream AOT
builder retain compiler/dependency ownership. It adds no selectable production
VM executor to the Rust library.
