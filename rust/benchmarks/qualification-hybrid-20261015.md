# ASCENT C ABI + AOT qualification — 2026-10-15

Historical receipt for the earlier executable. The [final qualification](qualification-hybrid-20261015-final.md)
includes the subsequent owner-lock cancellation fix and final rebuilt artifacts.

The public integration is implemented through the original Scheme ASCENT and the
pinned `gerbil-scheme-rust` bridge. The Rust Scheme evaluator has been removed.
Modules, components, closures, complex values and `Value.apply` execute through
the original VM. Rust owns typed finite data, Rayon execution, resource admission,
checked provenance and PyO3. There is no Python CFFI evaluator or JSON transport
of programs/results. AOT happens in the library build; runtime DSL loading does
not launch a compiler.

This is **completed local semantic qualification and an accepted isolated runtime
matrix** for the working tree based on `98f488964e6bc0ec49167c3fc7075e1d05e78637`.
The source hashes and executable bytes below identify the tested changes beyond
that commit. This report does not claim remote exact-head CI or Linux qualification.

## Semantic coverage

| Gate | Actual result |
| --- | --- |
| Original Scheme GxTest | 169 modules, 1,349 cases; exit 0; final `OK` |
| Workspace Rust, all features | 95 passed, zero failed/ignored |
| Rust warnings and repository policy | Clippy `-D warnings`, ASP gates passed |
| Original public Python semantic corpus | 34 files, 193 cases, every outcome `ok` |
| Installed PyO3 package | 15 passed |
| Independent workbench | 149 passed |
| Supervised installed consumers | 34/34 groups; 12.87s within unchanged 120s budget |
| Rust Ascent differential suite | 79 standard cases plus the explicitly executed original ignored scale case passed |
| Lean | 163 build jobs completed successfully |
| Quint | 52 model compilations; 66 correct-model checks and 270 expected fault counterexamples passed |

The supervised consumer gate checked 20,348 source/resource/test inputs before and
after execution, with zero drift. Its real-output watchdog remained unchanged.
The Quint rerun reused source-bound compilation artifacts; all 336 checking
obligations executed. Formal models support specified finite invariants; they
are not a proof of the C ABI or arbitrary Scheme programs.

Raw logs, individual test outcomes, the compressed consumer input receipt and
artifact hashes are in [the qualification directory](../tests/qualification-20261015/summary.json).

Cancellation covers queue admission, owner locks, native expansion/callbacks and
owned execution. Atomic replacement retains the previous committed generation
on rejection. Source duplicates count as occurrences, derived rows retain set
semantics, and native proof comparison preserves multiplicity. Provenance checker
version 3 rechecks generation and actual current source content, including
mutation outside replacement. Unsupported host callbacks never verify positively.

The full Scheme suite exposed an incorrect defensive copy in the typed-source
getter. The original API intentionally permits source mutation, revalidates on
fresh compilation, and owns already published programs. That original behavior
was restored. Original Scheme expectations were retained, and the Rust bridge
now checks rejection of invalid mutations plus preservation of old results.

## Matched measurements

Host: Apple M2 Pro, 12 physical/logical cores, 32 GiB RAM. Dev profile uses
optimization level 2 with overflow/debug checks. Each process loads the same
original Scheme DSL. VM execution uses one VM owner thread. Rayon execution uses
an owned finite projection, with 1/2/4/8/12 worker threads. The frontend still uses
one VM; this is not a multi-VM throughput experiment.

`K` is the number of independent components, `G` the number of disjoint chains per
component, and `W` the chain width. Every warmup and measured sample validates all
output tuples in Rust. Each configuration has one excluded warmup followed by
seven accepted samples. The table gives median **replace + execute + export**
wall time in milliseconds. VM replacement eagerly solves; timing only its cached
`run` would be an invalid comparison. Cold initialization/DSL loading and final
owner teardown are outside these steady-state timings.

| K/G/W | VM 1 | Rayon 1 | Rayon 2 | Rayon 4 | Rayon 8 | Rayon 12 | Best threads | VM / best | Rayon 1 / best |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1/16/16 | 9.452 | 0.885 | 0.900 | 0.911 | 1.090 | 0.899 | 1 | 10.68x | 1.00x |
| 1/256/16 | 136.453 | 16.408 | 15.484 | 12.472 | 13.099 | 15.187 | 4 | 10.94x | 1.32x |
| 8/32/16 | 141.528 | 14.002 | 13.198 | 12.067 | 21.571 | 12.729 | 4 | 11.73x | 1.16x |
| 1/32/64 | 281.597 | 37.777 | 31.925 | 25.598 | 31.982 | 33.652 | 4 | 11.00x | 1.48x |
| 1/2048/16 | 1123.847 | 182.944 | 141.887 | 111.849 | 109.189 | 109.920 | 8 | 10.29x | 1.68x |
| 8/256/16 | 1155.440 | 221.337 | 116.314 | 64.359 | 65.155 | 69.718 | 4 | 17.95x | 3.44x |

The VM comparison measures the whole execution path, including representation
and transfer costs. It is **not** a parallel speedup. Parallel speedup within
Rayon reaches 3.44x here. Four threads are fastest on four shapes, one thread on
the smallest shape, and eight threads narrowly win on K1/G2048/W16. Twelve
threads win on none. K8/G32/W16 at eight threads remains slower than Rayon 1
(21.571 vs 14.002ms). Increasing thread count is not a general improvement.

### Remaining cost in the accepted runs

Per-phase medians for each shape's fastest Rayon configuration:

| K/G/W | Threads | Replace ms | Execute ms | Export ms | Median replace+export share |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1/16/16 | 1 | 0.003 | 0.877 | 0.005 | 0.8% |
| 1/256/16 | 4 | 0.043 | 10.298 | 2.156 | 16.8% |
| 8/32/16 | 4 | 0.040 | 11.825 | 0.264 | 2.4% |
| 1/32/64 | 4 | 0.029 | 23.097 | 2.751 | 11.2% |
| 1/2048/16 | 8 | 0.433 | 104.946 | 2.137 | 2.4% |
| 8/256/16 | 4 | 0.308 | 60.039 | 5.165 | 8.8% |

Phase medians need not sum to the wall median. Most time remains inside execution.
That phase combines binding, set/index work, sorting and commit; these timings
do not causally separate those costs. Export alone does not explain the higher
thread-count regressions. No claim of linear scaling or a profile of individual
hash/allocator operations follows from this matrix. Rust Ascent remains only a
dev-dependency alignment control, not a production backend or a timing baseline.

## Isolation and retained failures

All builds and qualification processes owned by this task exited before timing.
The accepted matrix passed five seconds of quiet preflight and 89 process
snapshots at a half-second interval, with no compiler/checker interference
observed. Its complete source-input map was checked again after sampling.
This is one-host, seven-sample evidence without CPU affinity controls.

The first complete matrix also validated all 252 samples, but additional `gxi`
processes were observed. It was rejected for performance conclusions and retained
as [diagnostic data](results-hybrid-20261015-interference/acceptance.json).
Subsequent admission attempts did not start samples while another POO Flow
Java/Quint verifier was active. The accepted run waited for that verifier to exit.
The rejected run was not selected or discarded on timing values.

Other retained failures include the initial 120s native preparation timeout,
the typed-source contract failure, and a fork warning splitting unittest's
header/outcome line. The latter required a parser fix; missing outcomes still
fail the gate. Original deadlines and semantic assertions were not weakened.
Cold clean-build timing was not qualified by this runtime matrix.

## Receipts and reproduction

- [All 252 raw samples](results-hybrid-20261015/samples.tsv)
- [All 36 process exits and commands](results-hybrid-20261015/runs.json)
- [Source hashes, dependency pin and binary identity](results-hybrid-20261015/manifest.json)
- [Process audit](results-hybrid-20261015/process-audit.json), [source audit](results-hybrid-20261015/source-audit.json), [acceptance](results-hybrid-20261015/acceptance.json)
- [Isolation driver source](results-hybrid-20261015/isolation-driver.txt)
- [Semantic logs and wheel identity](../tests/qualification-20261015/summary.json)

Build and test first, then run the prebuilt harness with matching syntax resources:

```sh
GERBIL_HOME=/path/to/matching/sdk \
  python3 rust/benchmarks/run-hybrid.py \
  --binary rust/target/debug/hybrid-benchmark --output /new/receipt/directory
```

The harness records source hashes and rejects missing samples/failures/drift.
The separate isolation driver supplies process auditing; the command above alone
is not an isolation receipt. The binary SHA-256 in this accepted run is
`95c2dc1ac6823aef40036c221ffffaf7c0762316bbf03cd52df6f2fa58106794`.

Rayon remains the default feature. Rust Ascent and ASP Rust remain dev-dependencies.
The pinned upstream revision is `2c82b845c141ce68147cf74cb5a4ec680c6ffb07`.
Native DSL loading requires matching Gerbil syntax resources; the wheel is not a
standalone SDK. The upstream public Rust runtime currently admits one VM per
process, with one owning OS thread. Arbitrary host semantics remain in that VM;
forcing finite Rayon projection on unsupported semantics fails explicitly.
