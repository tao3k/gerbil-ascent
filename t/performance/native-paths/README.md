# Shared native path analysis

This change integrates one guarded path engine into `table/expression.ss`.
Canonical snapshots with 32–128 nodes and at least `ceil(3 * radix / 4)`
outgoing edges in every row use integer bit rows. Closure and shortest distance
share the same private breadth-first analysis. Source withdrawal and replacement
produce a fresh analysis through the existing POO snapshot demand mechanism.

## Contract and selection

- The default indexed source carries a fourth, private provenance marker. Its
  first three entries retain their meanings. Caller-supplied three-entry views
  continue through the general frontier engine.
- The native engine requires that marker and the original neighbor visitor's
  identity. Overriding `right-index` selects the general engine, preserving
  callback order and encoded-alias behavior.
- Low-degree rows are rejected before allocating bit rows. Sizes outside the
  selected band bypass the selector. Composition, delta steps, and two-hop
  projections retain their existing implementation.
- BFS starts with actual outgoing edges. A self distance requires a positive
  cycle; no zero-length identity is inserted. Distances remain boxed integers.
- An origin stops when no frontier remains or all targets have been seen.
  Neighbor-row unions also stop once their result covers the whole domain.
- Closure and distance publish separate sorted pair lists. Mutating a public
  list cannot change private membership, distance lookup, or the other list.
- Bounded closure runs a separate analysis without distance rows, counts all
  seeds before derived admissions, and throws before returning partial output.

This is a bounded selection policy, not a universal crossover model. A closure
query alone also prepares private distance rows on this path. The paired receipt
includes single-query, shared-query, complete-output, and fallback controls.
No global graph cache or additional production module is introduced.

## Semantic evidence

`oracle.ss` compares production against the exact preceding module at
`baseline.txt` and an independent positive-path Floyd–Warshall oracle:

- All 512 directed three-node graphs, including cycles and disconnected nodes.
- All 512 graphs embedded in a 32-node domain with the native row engine forced
  privately in the test, including budgets 0–9 and invalid budgets/queries.
- Automatic dense selection at 32, 33, 64, 65, 127, and 128 nodes, distance-first
  demand, shared analysis identity, separately mutable public lists, withdrawal,
  replacement, and callback overrides.
- A dense graph with an unreachable target, and a caller-supplied legacy view.
- Fallback size boundaries, sparse membership, long positive cycles at 512 and
  513 nodes, and callback traces against the frozen reference.

Only the two exported names are alpha-renamed in `reference.ss`; the collector
checks it against the exact Git source. Both modules must resolve to compiled
native artifacts. Sources and native artifacts are hashed before and after the
paired runs. The oracle requires final `OK` and rejects errors and overflows.

## Timing evidence

`benchmark.ss` runs 19 demand profiles with 20 warmups and two runs of 1,000
alternating old/new samples. Equality is checked outside the timed region.
Complete output includes at-most-two-hop pairs, closure pairs, distance pairs,
and every published distance lookup. Timing classification requires lower p50
and at least 900/1,000 paired wins in **both** runs. `primary` denotes a focus
profile, not a successful classification.

Raw paired samples, p50/p95, and wins are preserved in `first.sexp`,
`repeat.sexp`, and `report.json`. Allocation qualification remains withdrawn:
earlier runtime counter evidence included negative deltas. These receipts make
no allocation-savings claim.

Measured p50 in microseconds (old → new), with paired wins out of 1,000:

| Demand | First | Repeat | Wins first / repeat | Stable timing classification |
| --- | --- | --- | --- | --- |
| Complete output, degree 24 of 32 | 736 → 424 | 751 → 432 | 930 / 861 | No |
| Complete output, degree 31 of 32 | 942 → 544 | 955 → 551 | 899 / 867 | No |
| Complete output, degree 48 of 64 | 4393 → 2119 | 7692 → 2467 | 852 / 807 | No |
| Complete output, degree 63 of 64 | 5854 → 2923 | 11096 → 4031 | 839 / 794 | No |
| Closure alone, degree 31 of 32 | 612 → 325 | 618 → 328 | 947 / 898 | No |
| Distance alone, degree 31 of 32 | 424 → 335 | 429 → 337 | 944 / 860 | No |
| Distance then closure, degree 31 of 32 | 747 → 349 | 752 → 351 | 948 / 922 | **Yes** |

The broader intended timing assertion in `report.py` **failed**; its traceback
is retained in `timing-classification.log`. Both paired collectors and semantic
oracle completed successfully. Only the shared distance-then-closure profile
meets the stable timing criterion in these runs. The other dense profiles have
lower observed p50 and p95 in both runs, but must not be described as stable
timing-qualified improvements. Do not rerun samples until an assertion passes
or weaken the 900-win criterion. The production performance gates are recorded
separately from this experimental comparison.

Fallback p50 changes are small but not universally zero: the empty 64-node
distance demand changed from 13 to 14µs in both runs, and the empty 513-node
demand from 14 to 15µs in the repeat. The below-threshold degree-23/32 complete
output demand changed from 708 to 711µs and 721 to 724µs. Empty and sparse
512-node medians were unchanged. No cause of timing spread is established by
these receipts, and no general no-regression claim is made.

The exploratory 200-sample runs are preserved separately. `explore-manifest.json`
maps the initial implementation and oracle to frozen text and archived native
artifacts. `explore-early-manifest.json` identifies the early-completion variant;
its 128-node profiles are exploratory, not timing-qualified evidence.

## Production gates

All 41 production modules were compiled into one snapshot. The native module
resolution, 300 snapshot artifacts, and 299 dependency artifacts are recorded
in `production-snapshot.json` and `production-resolution.log`. The policy check
completed with zero findings and errors. All three original gates passed on the
first attempt; no fixture, sample count, threshold, or timeout was changed:

| Original gate | Candidate p95 | Outcome |
| --- | --- | --- |
| `ascent-table-expression` | 1.239ms | Pass |
| `ascent-table-expression-membership` | 26µs | Pass |
| `ascent-reachability-closure` | 91µs, 190 pairs | Pass |

These gates exercise their original fixtures; they do not establish stable
timing qualification for the dense profiles above. `gates.json` records process
statuses and raw gate logs retain semantic and harness markers.

Functional coverage is **48 modules / 373 Cases**, each with its Case, Module,
Harness, and final OK markers. The original whole-suite collection was
interrupted at its 360-second aggregate deadline (exit 124), after 46 modules
had passed. The retained-operator module was still reporting finite-graph
progress when terminated; the cleanup traceback is preserved as well. The two
incomplete modules were then run alone against the same verified native
snapshot and passed with their unchanged module/Case limits. This is complete
module coverage across an interrupted run and its completion, **not** a passed
uninterrupted suite invocation.

`final-functional-suite.log`, `suite-collection.log`, the two interrupted lane
summaries, and `interrupted-qualification/` retain the first attempt.
`completed-functional-suite.log` and `completed-suite.json` name the exact two
completion modules. `suite-coverage.json` and `qualification/` contain the final
verified module coverage. `final-verification.json` binds the final source,
paired samples, and native production/dependency artifacts to these receipts.

## Reproduction

Use the same installed dependency tree named in the receipts, or rebuild all
receipts against the replacement dependency tree. Local absolute artifact paths
in manifests refer to the original qualification checkout.

```sh
export GERBIL_PATH=/private/tmp/ascent-test-scheduling-gerbil
export GERBIL_BUILD_CORES=12
python3 tools/test_execution.py run -- python3 t/performance/native-paths/qualify.py
python3 t/performance/native-paths/report.py
python3 tools/test_execution.py run -- python3 t/performance/native-paths/gates.py
python3 t/performance/native-paths/run-suite.py > t/performance/native-paths/suite-collection.log 2>&1
```

Run the functional suite after the exclusive collectors have exited. Its own
module scheduler handles the shared/exclusive lanes; it must not inherit a
parent collector lease. The three original performance fixtures, sample counts,
and budgets are unchanged. Failed gates and any exact-snapshot recheck must both
be retained. Suite collection checks every Case, Module, Harness, and final OK
marker against the receipt, rather than accepting the process status alone.

If the aggregate 360-second collection deadline interrupts an otherwise
progressing run, preserve it and complete only the missing modules against the
same verified snapshot, with their original Case/module limits:

```sh
timeout 300s python3 t/performance/native-paths/complete-suite.py > t/performance/native-paths/completed-functional-suite.log 2>&1
```

This produces a combined coverage receipt with explicit interruption and
completion provenance. It must not be described as a successful uninterrupted
full-suite run.

After coverage is complete, run `python3 t/performance/native-paths/verify.py`
to verify the saved sources, artifacts, markers, and sample statistics. It
records the failed experimental timing assertion separately from successful
semantic coverage and original production gates.
