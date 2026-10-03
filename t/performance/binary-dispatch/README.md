# Binary execution and persistent result publication

This change follows one public query from validated declarations to bounded
execution and persistent result demand. The baseline is the exact committed
Ascent source in `baseline.txt` (ASP Scheme v0.1.2.2).

## Production changes

- Capture and validate sources before choosing the execution path. Initialize
  join indexes, membership tables, and pending epoch tables only for the general
  semi-naive evaluator. Replay indexed source rows in the original fold order,
  preserving observable guard callback order.
- Connect the public bounded closure helper used by the binary evaluator to the
  guarded native row engine. The preceding table prototype already used that
  engine, but this actual binary consumer bypassed it. Selection requires radix
  32 through 128 and every source row degree at least ceil(3*radix/4). Other
  graphs retain the general packed frontier. Existing positive path semantics,
  pair budgets, path names, rule selection, and validation remain unchanged.
- Publish captured canonical source rows without a second trie enumeration.
  Reuse immutable sets for unchanged underived inputs. Materialize derived sets
  on first demand and retain them for later demands. Every demand compares the
  public mutable row list with a private copy; edits before or after first
  demand rebuild a matching set. Existing returned sets retain their contents.
  General publication copies rows before sorting so even singleton inputs
  cannot alias the private captured snapshot.

The cache belongs to each evaluated result. It does not share mutable lists or
cache state between evaluations. This study makes no allocation claim.

## Reproduction

Use the isolated dependency environment recorded in the manifests and the
native build core setting, not an arbitrary worker count:

```sh
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil GERBIL_BUILD_CORES=12 \
  python3 tools/test_execution.py run -- \
  python3 t/performance/binary-dispatch/qualify.py
python3 t/performance/binary-dispatch/report.py
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil GERBIL_BUILD_CORES=12 \
  python3 t/performance/binary-dispatch/production.py
```

The matched collector holds one exclusive test lease. The production collector
runs performance gates under an exclusive lease, then releases it before the
functional module scheduler starts. Cases within a module follow std/test's
native order; independent shared modules use the configured 12-worker pool,
and exclusive modules run with isolation.

`reference-verification.json` checks frozen reference code against `git show`
with only exported identifier renames and the corresponding reference import
redirect. Four imported modules must resolve to native `.ssi` files in the
comparison library. Source hashes, all native comparison artifacts, and the
full external native dependency artifact set are checked during collection.

## Evidence boundaries

`oracle.ss` independently computes all 512 directed three-node graph closures,
including seeded heads, and embeds them at radix 3 and 32. It also compares
budget/error outcomes, dense and sparse dispatcher boundaries, guard traces,
and mutation of published rows against the frozen reference. Three permanent
regression cases cover dense total budgets, exact general guard order, and
persistent snapshots with pre/post-demand public edits including singleton
sources. Functional module receipts require CASE-OK, MODULE-OK, HARNESS-OK,
final OK, successful exit, and no overflow/error markers.

`criteria.json` defines timing qualification before results: 20 warmups, 1,000
alternating paired samples per run, two runs; lower p50 and at least 900 strict
paired wins in both runs. General copy/join/filter, seeded-head and radix-513
controls allow at most 10 percent p50 regression in either run. Complete
outputs are compared outside timers. Timers include evaluation and the declared
publication demand; fixtures are constructed beforehand. `materialized-31-32`
demands every native set once, while `repeated-31-32` demands all sets three
times from each evaluated result. These are bounded local measurements.

Raw early dispatch-only 200-sample exploration is preserved separately and is
not timing qualification. The initial oracle slot-shadowing stack overflow
and a later publication oracle syntax error were test-script defects; their
logs remain preserved. Neither failed run is used as successful evidence.

## Matched native results

Both native runs completed on one unchanged source/dependency snapshot. Eleven
of 18 profiles meet the predeclared timing qualification. All five general
controls remain within the 10 percent bound; their median change is 0 through
2.04 percent slower. There is no claim that every query becomes faster.

| Profile | p50 old → new (µs), first | p50 old → new (µs), repeat | strict wins / 1000 | Qualified |
| --- | ---: | ---: | --- | --- |
| empty-20 | 17 → 15 | 17 → 15 | 908, 884 | no |
| empty-128 | 25 → 15 | 26 → 15 | 992, 986 | yes |
| empty-512 | 38 → 16 | 38 → 16 | 996, 993 | yes |
| sparse-512 | 41 → 18 | 41 → 18 | 1000, 991 | yes |
| chain-20 | 51 → 39 | 50 → 39 | 985, 986 | yes |
| chain-128 | 444 → 379 | 446 → 380 | 964, 964 | yes |
| degree-16-32 | 665 → 499 | 667 → 501 | 969, 934 | yes |
| degree-24-32 | 942 → 481 | 943 → 482 | 968, 987 | yes |
| degree-31-32 | 1174 → 592 | 1171 → 591 | 966, 976 | yes |
| degree-48-64 | 4535 → 1972 | 4521 → 1961 | 938, 939 | yes |
| degree-63-64 | 5821 → 2476 | 5828 → 2482 | 935, 952 | yes |
| materialized-31-32 | 16953 → 8840 | 17237 → 8993 | 896, 912 | no |
| repeated-31-32 | 52688 → 10010 | 52520 → 10138 | 989, 980 | yes |
| general-copy-32 | 223 → 226 | 221 → 224 | 181, 175 | no |
| general-join-32 | 49 → 50 | 49 → 49 | 257, 228 | no |
| general-guard-32 | 249 → 251 | 248 → 250 | 265, 204 | no |
| seeded-32 | 166 → 169 | 165 → 168 | 144, 93 | no |
| sparse-513 | 13 → 13 | 13 → 13 | 320, 203 | no |

The qualified 32-node degree-31 closure reduces p50 by about 50 percent; the
64-node degree-63 case reduces it by about 57 percent. Three complete native
set demands on one degree-31/32 result reduce p50 by about 81 percent. The
first materialization profile improves its p50 by about 48 percent, but its
first-run 896 strict wins fall short of 900; it is **not timing qualified**.
The empty radix-20 case also misses the repeat-run win threshold. Neither is
rerun to change that classification. All raw arrays and recomputed p95 values
are retained in `first.sexp`, `repeat.sexp`, and `report.json`.

The earlier production collector was started while the matched collector held
the exclusive lease. It expired the scheduler's unchanged 120-second queue
limit before executing tests. `lane-wait-timeout-*.log` preserves this scheduling
failure. The collector was started after the lease was released. No per-test
or per-module deadline was relaxed.

## Production qualification and final audit

One native production snapshot resolved all 41 modules to its own compiled
library. The full external native dependency manifest contains 1,080 artifacts
and stayed unchanged through both matched runs, the original performance
gates, policy build, and the full functional suite. `verification.json`,
`production-snapshot.json`, `production-resolution.log`, and
`native-dependencies.json` retain these boundaries.

All original gates passed on their first executed run, without changing fixture
budgets or the 1,000-sample settings:

| Original gate | Candidate p95 | Existing maximum |
| --- | ---: | ---: |
| table expression | 352 µs | 2,000 µs |
| expression membership | 14 µs | 500 µs |
| reachability closure | 81 µs | 1,000 µs |
| binary program | 70 µs | 2,000 µs |

The policy build reported zero findings and zero errors. The full functional
suite passed **48 modules / 376 Cases** in 173.4 seconds: 33 shared modules
used the configured 12-worker scheduler, followed by 15 isolated modules.
All per-module logs are retained in `modules/`; `suite-coverage.json` records
every passing Case. There was no performance gate recheck.

Run `GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil python3
t/performance/binary-dispatch/verify.py` from the repository root to check
source/artifact hashes, recompute statistics, validate gate markers, and audit
all module receipts. `final-audit.json` also records expected Git blob identities
for the two changed production modules and the permanent regression file.
These are local native receipts; remote CI and deployment are not established
by this study.
