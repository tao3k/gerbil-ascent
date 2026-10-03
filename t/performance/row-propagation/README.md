# Closed relation row propagation study

## Question and code seam

Production `table/expression.ss` publishes ordered packed pairs, but its closure
and distance kernels still enumerate the neighbors of each newly reached pair.
A high fanout graph repeats target admission work. This study replaces that inner
loop with whole adjacency row unions and measures construction plus demanded
public results. Production remains at the commit in `baseline.txt`.

`kernel.ss` contains two native Gerbil prototypes:

* **frontier**: per origin, expand a bitmask frontier by ORing adjacency rows,
  mask out seen nodes, and assign the current BFS depth. Closure and distances
  share the resulting private analysis.
* **warshall**: compute closure by Boolean Warshall row unions. Distances still
  use the frontier algorithm, so complete-output demand pays both traversals.

These are bit operations inside one process. They do not change test scheduling
or `GERBIL_BUILD_CORES`, which controls native compilation workers.

The [GraphBLAS C API 1.2, Appendix B.1](https://graphblas.org/docs/GraphBLAS_API_C_v1.2.0.pdf)
expresses BFS as Boolean frontier-vector / adjacency-matrix multiplication with
a complemented visited mask. Its example starts with the root; ASCENT requires
positive-length paths. This prototype starts with actual outgoing edges, assigns
those distance one, and allows the origin to be reached later through a cycle.
The independent oracle explicitly tests this difference.

For Boolean closure the implemented recurrence is
`R[from] |= R[via]` when `via` is present in `R[from]`, with no added reflexive
identity. Closure-only Warshall costs up to radix squared bit tests plus row
unions; it does not compute distance labels. Frontier BFS visits each reachable
vertex once per origin but unions a row for each visited vertex. Neither cost
model alone predicts the crossover once output publication and allocation are
included.

## Representation and semantics

Adjacency and reachable rows are arbitrary precision Gerbil integers, scanned
in 16-bit chunks. Canonical pair publication scans from high source to low and
conses descending targets. Distance rows are allocated only for origins with
outgoing edges, using unsigned 16-bit vectors; zero means absent. For the
supported radix 2..512 every shortest positive path fits in that representation.
Closure and distance public lists are separate publications, while analysis is
private and shared.

Budgeted closure counts every source edge before admitting derived masks. A
mask may be admitted as a private batch before the budget error is raised; no
partial projection is returned. The budget error string and acceptance boundary
are checked. The study does not preserve the observable traversal order of an
overridden neighbor callback.

## Evidence and reproduction

Use the existing installed Gerbil package environment and execute:

```sh
GERBIL_PATH=/private/tmp/ascent-test-scheduling-gerbil GERBIL_BUILD_CORES=12 \
  python3 tools/test_execution.py run -- \
  python3 t/performance/row-propagation/qualify.py
python3 t/performance/row-propagation/report.py
```

The qualifier holds the exclusive measurement lane, builds both native modules,
verifies the exact frozen reference against Git with only two export name
changes, runs the oracle, and performs two paired benchmark runs. Each benchmark
checks actual SSI import paths, compares full demanded results outside timers,
and retains all 1000 alternating paired samples after 20 warmups. Timers include
fresh expression construction and output consumption; inputs are prepared first.
Raw byte counter deltas come from Gambit process statistics; see the measurement limitation below. Results include medians,
p95s and paired wins. Report flags require lower medians and at least 900 wins
in each run; they summarize observations rather than enforce production gates.

`oracle.ss` compares both prototypes against an independent positive-path
Floyd-Warshall matrix for all 512 directed three-node graphs, including loops.
It checks closure, distance rows and every lookup, compares two-hop publication
with the frozen production module, and checks budgets 0..9. Eleven additional
radices cover word, fixnum and dense limit boundaries through 512.

The two initial failures are preserved: `failed-oracle-syntax.log` records an
unclosed oracle binding; `failed-oracle-stack.log` records a POO constructor
parameter named `radix` recursively referring to its own slot. The corrected
constructor uses an external `width` parameter. These failures are excluded from
passing evidence and neither required a production change.

## Production transfer requirements

This is an experimental closed, static, unit-weight graph implementation. It
is not a replacement for the public production prototype: custom `right-index`
callbacks, `indexed-source`, `delta-step`, `closure-set`, sparse radix above 512,
and snapshot withdrawal have not been qualified here. Its wrapper also exposes
fewer slots, so native timings do not include full production integration costs.

A production integration must preserve callback observability, retain the sparse
path, qualify composition/delta and snapshot withdrawal, and select any dispatch
rule from reproducible demand and graph regimes. Shared private BFS analysis
must not change externally observable caching or mutable result behavior. Full
production native suite and performance gates remain required after integration.

## Results and decision

Both native runs completed all 24 comparisons, with equal demanded outputs.
The reference is production commit `10288b7`. The table gives the two old/new
wall-time medians in microseconds, followed by candidate paired wins per 1000.
Timing qualification requires a lower median and at least 900 wins in both runs.

| Workload | First old / new us | Repeat old / new us | Wins first / repeat | Timing qualified |
|---|---:|---:|---:|---|
| frontier-complete-32-degree-1 | 119 / 387 | 114 / 384 | 34 / 24 | False |
| frontier-complete-32-degree-2 | 154 / 378 | 152 / 375 | 36 / 39 | False |
| frontier-complete-32-degree-4 | 216 / 391 | 215 / 390 | 48 / 64 | False |
| frontier-complete-32-degree-8 | 341 / 428 | 338 / 425 | 88 / 68 | False |
| frontier-complete-32-degree-16 | 599 / 506 | 592 / 501 | 865 / 901 | False |
| frontier-complete-32-degree-31 | 1101 / 637 | 1087 / 630 | 902 / 915 | True |
| frontier-complete-fanout-64 | 26811 / 2820 | 9586 / 2761 | 822 / 892 | False |
| frontier-projection-256 | 301 / 564 | 302 / 568 | 66 / 81 | False |
| frontier-closure-chain-32 | 44 / 67 | 44 / 67 | 38 / 18 | False |
| frontier-distance-chain-32 | 53 / 193 | 54 / 194 | 26 / 28 | False |
| frontier-empty-distances-512 | 111 / 23 | 109 / 23 | 991 / 991 | True |
| frontier-sparse-distances-512 | 113 / 27 | 112 / 27 | 985 / 993 | True |
| warshall-complete-32-degree-1 | 114 / 391 | 122 / 396 | 20 / 31 | False |
| warshall-complete-32-degree-2 | 154 / 388 | 152 / 385 | 49 / 28 | False |
| warshall-complete-32-degree-4 | 217 / 400 | 215 / 398 | 62 / 38 | False |
| warshall-complete-32-degree-8 | 341 / 436 | 340 / 436 | 96 / 82 | False |
| warshall-complete-32-degree-16 | 600 / 514 | 595 / 511 | 863 / 869 | False |
| warshall-complete-32-degree-31 | 1098 / 645 | 1098 / 646 | 894 / 880 | False |
| warshall-complete-fanout-64 | 23500 / 2952 | 26204 / 2961 | 833 / 823 | False |
| warshall-projection-256 | 299 / 563 | 299 / 564 | 64 / 68 | False |
| warshall-closure-chain-32 | 43 / 40 | 43 / 40 | 949 / 959 | True |
| warshall-distance-chain-32 | 53 / 192 | 53 / 193 | 22 / 18 | False |
| warshall-empty-distances-512 | 111 / 23 | 110 / 23 | 991 / 987 | True |
| warshall-sparse-distances-512 | 113 / 26 | 113 / 27 | 978 / 982 | True |

**Measurement limitation:** both runs retain 152 negative byte counter deltas
among 48,000 observations. Their cause has not been established for the installed
Gambit runtime. Allocation qualification is therefore withheld for this entire
study. Legacy receipt field names contain `bytes` and `paired-wins`; report.json
separately marks these as counter observations, not qualified allocation savings.
Samples have not been filtered or silently discarded. An audit of the preceding
ordered-relations receipts also found 86 negative deltas among 20,000 observations
in each run; its README.org now withdraws that allocation qualification while
preserving the historical data. Timing calculations are
independent of the byte counter; p95s and raw timings remain in the receipts.

The frontier complete-output case at radix 32, degree 31 improves its median
from 1087–1101 us to 630–637 us, with 902/915 paired wins. This meets the local
study criterion. At radix 64 the medians are much lower but paired wins do not
reach 900 in both runs; a stable timing claim is withheld. There is substantial
wall-time spread in those measurements, without a proved cause.

Empty and sparse distance queries at radix 512 improve from 109–113 us to
23–27 us. The row storage direction is supported by time and output evidence;
its byte savings still need a corrected allocation measurement. It is the most
promising first production migration seam, retaining the existing traversal and
callback behavior while replacing full distance matrices with optional rows.

Uniform frontier propagation is rejected: degree 1..8 complete graphs, cold
projection and chain distances regress. Chain distances take roughly 193 us
versus 53 us despite the shared analysis design. Warshall closure-only on a
32-node chain qualifies at 40 us versus 43 us, but its complete demand adds a
second closure traversal and fails the paired timing criterion at high density.
These results do not establish a universal density threshold or justify an
unconditional replacement.

A coherent next implementation should qualify optional distance rows first,
then evaluate a guarded native row frontier path for dense complete demand.
Required experiments include the complete production wrapper, callback overrides,
snapshot withdrawal/replacement, sparse >512 fallbacks, and existing native
functional/performance gates. Allocation instrumentation must be corrected before
using memory savings to select an execution strategy. No production rollout or
remote push is part of this research receipt.
