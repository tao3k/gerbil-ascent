# Scheme execution runtime comparison — 2026-10-14

Historical measurements, not qualification of the current wheel. Referenced
`results-*` artifacts are local-only and deliberately excluded from Git.
These results do not establish current consumer performance closure.

Rayon provides a modest parallel benefit on the larger inputs in this local
measurement, not linear scaling. Four workers reduce median elapsed time by
16.3%–19.8% against one-worker Rayon (1.19×–1.25× speedup). Small inputs and
the longer recursive chain slow down as workers increase. Twelve workers do
not beat four workers on any measured shape.

## Runtime and implementation boundaries

The intended production comparison is our Scheme implementation running under
two runtime arrangements: Scheme Actor execution and Rust Rayon execution.
Upstream Rust Ascent remains a **dev-dependency for independent alignment**;
its timings below are a reference, not a third production backend.

The Scheme/Gambit constraint is **multiple VMs, each single-threaded**. This
must not be confused with multiple OS threads executing one shared VM. The
upstream multi-threading/GC gap is the reason to prioritize Rust's working
Rayon thread pool. This benchmark does not qualify an upstream GC repair.
The installed SDK's `gambit.h` supports `___MULTIPLE_VMS` and defaults to
`___SINGLE_THREADED_VMS`; the executable reports `vm-processors=1`.

The Actor measurements here invoke the existing `gerbil-ascent-open-actor-session`
API. Its round scheduler uses `spawn/name` and message passing. The benchmark
launches one Scheme executable per configuration; it does **not** instantiate
multiple VMs inside that executable. Consequently, worker capacities 1/2/4/8/12
measure this local Actor scheduling path, not multi-VM multicore scaling. A
separate multi-VM launcher and its communication/partitioning costs remain
unmeasured. Actor capacity, VM count, and OS thread count are distinct quantities.

There is also a current implementation gap: `program/rust-execution.ss`
generates matching, rule composition, and round composition through the pinned
Scheme-to-Rust compiler. Rust still supplies newly written admission, index,
binding-batch, storage, budget, and publication kernels. The existing Scheme
evaluator is not fully translated into those same kernels. Cross-runtime
latency differences therefore mix implementation and runtime differences;
they are **not** evidence of a pure scheduler substitution. The parallel
speedup calculation compares the same Rayon implementation against Rayon(1).

## Method

- Local `aarch64-apple-darwin`, macOS 26.6.1, 12 logical CPUs; Rust 1.95.0.
- Checkout baseline `f53a9a3` on `feature/ascent-scheme-syntax`, plus the uncommitted
  Rust implementation and benchmark files. [Manifest](results-20261014/manifest.json)
  records source/binary SHA-256 values. These are local results, not CI results.
- Scheme entry and imported production modules compile through upstream Gerbil
  `std/make`/`compile-exe` into a linked executable. Production source timestamps
  were not newer than the canonical `.ssi` artifacts. Rust uses the release/bench
  profile, thin LTO, and enabled overflow checks.
- Each shape is `K` independent relation/rule components, each containing `G`
  disjoint chains of `W` nodes. Input rows = `K*G*(W-1)`; reachability output
  rows = `K*G*W*(W-1)/2`. Independent data chains in one relation do not create
  separate rule SCCs. K=8 explicitly creates eight rule SCCs.
- One untimed warmup and seven retained samples per configuration: 6 shapes ×
  12 configurations × 7 = **504 successful samples / 72 configurations**.
  Every sample compares every output tuple against the exact independently
  enumerated chain closure; the Rust oracle is also checked tuple-for-tuple.
- Timed span: fresh declaration/session admission, source replacement, complete
  solve, and output access/export. Input/expected-row generation, executable
  startup, compilation, exact result assertion, and output printing are excluded.
  Each sample uses a fresh session; no completed-result cache hits are timed.
- The Rust pool is created before timing and reused across samples. Scheme's
  owner creation and per-round worker scheduling remain inside its public
  session operations. The different lifecycle costs are part of the reported
  measurements, not normalized away.
- `Session.run` on Rust already sorts/publishes all relations; its export column
  additionally clones the requested immutable row handles. Scheme's output
  access/export sorts its requested relation lists. The reference Rust oracle
  uses statically generated integer-tuple rules and performs sorting in export.
  Its zero-cost dynamic-admission column is not comparable to Scheme admission.
- Runs execute sequentially without affinity or system-load isolation. Each
  configuration's seven samples run together, in ascending worker order; these
  are descriptive medians/ranges, not randomized paired confidence estimates.
- Scheme max heap is 2 GiB. Both implementations have finite work/fact limits,
  but their work counters do not have identical semantics. Rust and the serial
  Scheme control use a 30-second deadline; Actor has no `.run-timeout` slot and
  uses its ordinary run API. Every process has a 150-second external watchdog.
  No valid configuration exhausted a budget or watchdog.

## All measured shapes

Median elapsed milliseconds, seven samples each. `S0` is the same generated
Scheme/Rust execution path with parallel iterators disabled; `R1...R12` are
Rayon worker counts. `A1` is the existing Scheme Actor path with capacity one.
All Actor capacities and sample ranges are retained in
[summary.tsv](results-20261014/summary.tsv); no best samples were selected.

| K / G / W | A1 | S0 | R1 | R2 | R4 | R8 | R12 | Rust oracle |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 / 16 / 16 | 10.65 | 1.10 | 1.12 | 1.21 | 1.25 | 2.35 | 2.28 | 0.17 |
| 1 / 256 / 16 | 92.06 | 20.26 | 20.03 | 21.58 | 21.84 | 25.96 | 25.59 | 2.89 |
| 8 / 32 / 16 | 107.64 | 20.70 | 19.81 | 22.04 | 18.14 | 22.50 | 23.09 | 2.81 |
| 1 / 32 / 64 | 484.60 | 40.73 | 43.40 | 48.48 | 51.65 | 51.94 | 66.15 | 5.39 |
| 1 / 2048 / 16 | 893.13 | 223.96 | 233.35 | 222.54 | 195.40 | 196.87 | 206.69 | 27.32 |
| 8 / 256 / 16 | 730.98 | 189.32 | 186.74 | 183.05 | 149.70 | 151.05 | 163.98 | 24.70 |

The last two shapes have the same 30,720 input rows and 245,760 output rows.
Against Rayon(1), their four-worker speedups are **1.194×** and **1.247×**;
against S0 they are **1.146×** and **1.265×**. Twelve-worker speedups against
Rayon(1) fall to **1.129×** and **1.139×**. These are workload-specific local
observations, not a general 25% gain. The longest-chain shape reaches 1.52×
slowdown at 12 workers versus Rayon(1).

For K=8/G=256/W=16, median phase times are:

| Configuration | Admit | Replace | Solve/publish | Export/access | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Scheme Actor(1) | 27.26 | 0.89 | 681.82 | 19.74 | 730.98 |
| Scheme AOT serial | 0.06 | 0.95 | 187.31 | 2.44 | 189.32 |
| Scheme AOT Rayon(1) | 0.03 | 0.94 | 183.08 | 1.90 | 186.74 |
| Scheme AOT Rayon(4) | 0.04 | 0.98 | 146.37 | 4.21 | 149.70 |
| Scheme AOT Rayon(12) | 0.04 | 0.93 | 160.91 | 2.40 | 163.98 |
| Rust Ascent oracle | 0.00 | 0.01 | 20.10 | 4.53 | 24.70 |

Phase medians need not sum to the total median. The main remaining cost is
solve/publication, not source replacement or external data transport. The
oracle's much lower latency identifies room to investigate generic owned-value
and checking costs; it does not justify replacing the production implementation
with the dev-dependency or claiming equivalent feature coverage.

## Bottleneck evidence and next experiments

Separate five-second, 1 ms `sample` runs collected call stacks for Actor(1) and
Rayon(4), using K=8/G=256/W=16. Profiling samples are **excluded** from the 504
latency samples. Top-of-stack counts are observations across threads, including
sleeping threads; they must not be read as wall-time percentages.

Rayon top stacks include `mach_absolute_time` (2220), `Budget::fact` (967),
`DashMap::_insert` (341), allocator tiny allocations (423), free (355), and
binding construction. Condition-variable waits (9333) include the caller
waiting for its installed job and idle workers. This is evidence of budget,
clock, allocation, hash/dedup, and idle/synchronization costs, not proof that
mutex contention alone dominates. Source inspection explains the clock cost:
`Budget::work` and `Budget::fact` each poll the deadline on their hot paths.
Bindings clone vectors, indexed probes allocate keys, and each published fact
passes global deduplication before serial round publication/index insertion.

Scheme top stacks include runtime table (662), runtime hash (129), rule plans
(329), index (237), and GC `mark_array` variants (427 + 257). GC and generic
storage/traversal are visible, alongside Actor messages; this does not quantify
the benefit of a future upstream GC repair. The source also exposes fixed
public declaration/admission costs that matter especially on small graphs.

A separate unprofiled `/usr/bin/time -p` pass (one warmup + seven full operations,
including process setup/assertions) measured average CPU utilization of about
0.99 core for Rayon(1), **2.50 cores for Rayon(4)**, and **4.38 cores for
Rayon(12)**. The twelve-worker process consumed about 6.35 CPU-seconds versus
3.32 at four workers, while taking 1.45 versus 1.33 elapsed seconds. More workers
perform more CPU work without reducing latency here. This diagnostic pass is
not mixed into the primary medians.

Priorities supported by these observations:

1. Amortize deadline sampling and global work charging in bounded batches,
   preserving exact fact-limit admission, prompt cancellation, and final checks.
   Compare reduced clock traffic against cancellation latency, not speed alone.
2. Use worker-local candidate batches/deduplication, then owner-checked merge;
   preserve exact global resource accounting and no-partial-publication behavior.
   Measure this against the existing DashSet path before removing synchronization.
3. Reduce binding/key allocation and row cloning with typed slots/owned batches;
   investigate serial index maintenance and deterministic publication separately.
4. Tune task splitting/serial cutoffs by actual work. Extra workers hurt the
   small and long-chain controls; a larger pool is not automatically better.
5. Qualify an explicit multi-VM Scheme harness separately, including isolation,
   input partitioning, cross-partition fixed-point communication and merge costs.
   A process-per-component throughput result alone would not establish Actor
   session latency or general shared-graph correctness.

No production optimization or runtime-selection policy was changed during this
measurement. Four workers are the best measured setting on these larger cases;
these data do not justify setting four as a universal default.

## Receipts and reproduction

- [Raw samples](results-20261014/samples.tsv), [all configurations and ranges](results-20261014/summary.tsv),
  [run statuses](results-20261014/runs.json), and [source/binary identity](results-20261014/manifest.json).
- [Rayon top stacks](results-20261014/rayon4-top-stacks.txt),
  [Scheme top stacks](results-20261014/actor1-top-stacks.txt).
- Full local stacks and process/resource outputs remain in
  `.cache/ascent/runtime-comparison-profile-20261014`.
- Four exploratory non-Actor retained-session controls failed because that API
  requires an initial run before source replacement. Their diagnostics are
  retained with the receipts; they contributed no timing samples. The runner
  now requests only valid Actor capacities for Scheme. There were 76 attempted
  configurations, 72 successful measured configurations, and no concealed
  semantic mismatch or timeout in those 72.
- The first sandboxed sampling attempt could not attach. Sampling the benchmark
  process outside the sandbox succeeded. `time -l` also failed on restricted
  `sysctl kern.clockrate`; the successful `time -p` diagnostic replaced it.

From the repository root, using the selected Gerbil SDK environment and normal
project `GERBIL_PATH`/linker settings:

```sh
mkdir -p .cache/ascent/rust-rayon
gxi rust/benchmarks/build-scheme.ss
cargo bench --manifest-path rust/Cargo.toml -p gerbil-ascent \
  --bench runtime_comparison --no-run --locked
# Use the executable path printed by Cargo for --rust.
python3 rust/benchmarks/run-comparison.py \
  --scheme "$PWD/.cache/ascent/rust-rayon/scheme-runtime" \
  --rust "$PWD/rust/target/release/deps/runtime_comparison-<cargo-hash>" \
  --output "$PWD/.cache/ascent/runtime-comparison"
# Add --large for the matched 245,760-output-row cases.
python3 rust/benchmarks/summarize.py \
  .cache/ascent/runtime-comparison/samples.tsv --output /tmp/ascent-summary.tsv
```
