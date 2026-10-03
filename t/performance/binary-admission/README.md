# One admission ledger for the general binary fixed point

This change follows one evaluation through source capture, admission, join
rounds, commit, budgets and immutable result publication. The preceding commit
is frozen in `baseline.txt`; reference modules differ only in exported names
and the corresponding import redirect.

## State model

Previously each derived relation had a committed membership table and a
separate table containing the pending epoch for every possible pair. The
latter prevented duplicate emission within a round; the former prevented
emission of source or already committed facts. Both were private to one query.

The candidate keeps one monotone admission ledger. Validated source facts are
marked during initialization. Each previously absent emitted fact is marked
before budget checks and queued in the same pending list as before. Rules
still consume all/delta rows and their adjacency indexes; they never consume
the admission ledger. All pending rows commit after all rules in the same
order. Marking a pending bit cannot expose that row to another rule early.
Subsequent rounds need no epoch counter or pending table. A budget failure
aborts the query without publishing partial results, so no rollback ledger is
needed. A fresh query always creates fresh private state.

For radix <= 512, sixteen pair flags occupy one u16 word. Pair validation and
bounded joins prove all dense keys are in range and fit fixnums. Larger domains
use one hash table for both pending and committed membership, replacing two
hash tables. Source snapshots, callbacks, input/derived/output budgets,
validation errors, join/index order, fixed-point visibility and canonical
publication retain their preceding behavior. Specialized closure queries do
not allocate this general state.

This is a representation and lifecycle change across every general rule
combination. No measured allocation or resident-memory claim is made; packed
flag capacity does not establish live process memory consumption.

## Qualification contract

Two native runs use 20 warmups and 1,000 alternating paired samples per profile.
Timing qualification requires lower p50 and at least 900 strict paired wins
in both runs. Copy/join/filter and two specialized queries are controls with a
10 percent p50 regression bound. All outputs are compared outside timers;
timers include complete evaluation and canonical pair-list publication.
Fixture objects and persistent input sets are constructed beforehand.

Seeded chain and cyclic profiles force general execution. Independent seeded
heads extend along read-only 19-edge chains at radix 32/128/512, with sparse
radix-513 comparison. The radix-512/32-head case exercises initialization of
many derived membership tables over a large bounded domain.

The independent oracle evaluates all 512 three-node directed graph closures
at radix 3 and 32, including seeded heads and exact budget/error comparisons.
It also checks dense/sparse boundaries, guard traces and public result-list
mutations against the preceding native implementation. Existing multi-target,
two-changing-input and delayed-index activation regressions are retained.
Two new permanent cases cover duplicate pending admissions across rules and
separate heads, and bit positions 0/15/16/final at radix 5/32/512/513 including
padding and the dense-to-sparse boundary.

## Reproduction

```sh
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil GERBIL_BUILD_CORES=12 \
  python3 tools/test_execution.py run -- \
  python3 t/performance/binary-admission/qualify.py
python3 t/performance/binary-admission/report.py
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil GERBIL_BUILD_CORES=12 \
  python3 t/performance/binary-admission/production.py
GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil \
  python3 t/performance/binary-admission/verify.py
```

Start the production collector after matched collection releases its exclusive
lease. Performance gates run with isolation; the functional suite starts
outside that lease with the configured native scheduler. Native resolution,
source/reference hashes, compiled artifacts, and the full external dependency
artifact set are checked. These are local receipts, not remote CI evidence.
Original fixture admission thresholds and sample counts remain unchanged.

## Matched native results

Four of 12 profiles meet the predeclared timing qualification in both runs.
All five controls have equal or lower p50, within the 10 percent regression
bound. No failed qualification is rerun to change its classification.

| Profile | First p50 old → new (µs) | Repeat p50 old → new (µs) | Strict wins / 1000 | Qualified |
| --- | ---: | ---: | --- | --- |
| seeded-chain-20 | 42 → 40 | 42 → 40 | 870, 832 | no |
| seeded-chain-48 | 161 → 152 | 162 → 153 | 959, 928 | yes |
| seeded-degree-2-32 | 160 → 151 | 160 → 151 | 926, 936 | yes |
| right-inputs-8-32 | 127 → 120 | 127 → 120 | 957, 948 | yes |
| right-inputs-32-128 | 539 → 463 | 532 → 462 | 956, 898 | no |
| right-inputs-32-512 | 5449 → 519 | 4001 → 548 | 973, 992 | yes |
| right-inputs-8-513 | 189 → 169 | 186 → 166 | 793, 859 | no |
| general-copy-32 | 229 → 223 | 231 → 226 | 811, 853 | no |
| general-join-32 | 50 → 48 | 49 → 48 | 875, 868 | no |
| general-guard-32 | 220 → 217 | 224 → 221 | 836, 817 | no |
| specialized-chain-20 | 39 → 39 | 39 → 39 | 375, 367 | no |
| specialized-degree-31-32 | 604 → 603 | 613 → 611 | 523, 546 | no |

The bounded 512-domain / 32-derived-head query reduces p50 by 90.5 percent
and 86.3 percent in the two runs. The 48-node seeded chain, 32-node cyclic
graph and eight-head radix-32 case improve p50 by approximately 5.5 percent
and meet both strict paired-win requirements. The radix-128/32-head case
misses the repeat-run threshold with 898 wins and is **not qualified**, despite
lower medians. The sparse radix-513 case, smaller chain and copy/join/filter
controls also have lower medians but are not timing qualified. Specialized
controls are unchanged code paths and are not claimed as improvements.
Raw arrays and recomputed p50/p95/wins remain in the receipts and report.

This is a complete-query timing result for the stated shapes. It does not
establish an 86–90 percent speedup for arbitrary binary programs or measured
allocation savings.

## Production qualification and final audit

All 41 production modules resolve to one compiled snapshot. The isolated ASP
v0.1.2.2 / POO dependency pins and 1,080 external native artifacts remain
unchanged across the matched measurements, policy build, original performance
gates and full functional suite. Sources and native artifacts are checked
before/after execution.

The full suite passes **48 modules / 380 Cases** in 394.5 seconds: 33 shared
modules use the configured 12-worker pool, followed by 15 isolated modules.
Every Case, module, harness and final OK marker is checked with successful
exit and no overflow/error markers. Both new admission regressions pass.
Per-module logs, native resolution, suite receipt and complete coverage are
retained. The aggregate deadline remains 600 seconds; per-module deadlines
are unchanged.

All four original 1,000-sample performance gates pass on their first executed
run with unchanged admission budgets:

| Original gate | Candidate p95 | Existing maximum |
| --- | ---: | ---: |
| table expression | 800 µs | 2,000 µs |
| expression membership | 26 µs | 500 µs |
| reachability closure | 146 µs | 1,000 µs |
| binary program | 118 µs | 2,000 µs |

Policy reports zero findings and zero errors. There is no gate recheck in this
study. The preceding commit's table-expression failures remain preserved in
`../general-rounds/`; that module's source is unchanged in this commit. Its
current passing measurement does not establish that the admission ledger
caused the earlier percentile failure or repaired the table-expression path.

`verify.py` independently recomputes matched statistics and rechecks source,
reference, artifact, dependency and per-module evidence. `final-audit.json`
records these checks and Git blob identities for post-commit source validation.
These are local native receipts; remote CI and deployment are not verified.
