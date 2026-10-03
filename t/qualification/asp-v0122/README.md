# ASP Scheme v0.1.2.2 dependency upgrade

Ascent's declaration changes from `v0.1.2.1` to `v0.1.2.2`. The remote annotated
tag object is `0b59cb7d6d29d545ae735741057452bdb5e77aea`, pointing to commit
`f5b7c009d2cab61144a8af18008a0bfba3056584`. The release fixes native prelude
import closure and build/test contracts. Existing consumer API calls are retained.

The two other dependency commits remain unchanged:

- POO Flow Core: `e85fd45303b208b23e5957fd316e7004994109a4`.
- Gerbil POO: `099b381588360a8a49fd772f666a1a00351366f5`.

## Environment and provenance

The upgrade was installed in `/private/tmp/ascent-asp-v0122-gerbil`, copied from
the prior isolated dependency environment before updating ASP. The original
environment and preceding performance receipts remain available. The package
manager's tagged `update` checked out the correct release, then failed in
dependency traversal with `bad package; missing gerbil.pkg`; that failure is
preserved in `update-tag-error.log`. `gxpkg deps --install` then completed the
declared dependency installation and native ASP build successfully.

`asp-native-resolution.log` identifies the building and benchmark `.ssi`
modules. `asp-loaded-binaries.log` records the runtime-selected **new `.o2`**
binaries for building API, package specification, and native import closure.
The earlier malformed diagnostic expression and the preparation check that
initially rejected the builder-generated `manifest.ss` are retained separately;
neither is a successful qualification receipt. The qualifier allows that one
generated untracked manifest and rejects dependency source changes.

The installed dependencies contain both `.so` and Gambit `.oN` artifacts.
`native-dependencies.json` hashes all 1,080 relevant native and interface
artifacts, including the `.oN` binaries, before and after qualification.
`production-snapshot.json` additionally binds all 41 production source modules
and their newly compiled artifacts. Module resolution is recorded in
`production-resolution.log`.

## Reproduction

```sh
export GERBIL_PATH=/private/tmp/ascent-asp-v0122-gerbil
export GERBIL_BUILD_CORES=12
gxpkg deps --install
python3 t/qualification/asp-v0122/qualify.py > t/qualification/asp-v0122/collection.log 2>&1
```

Use the dependency versions recorded in `dependency-pins.json`. The collector
runs policy and the three original relation performance gates under an
exclusive lease. It then releases that lease before running the native module
suite with 12 workers. Each Case and module keeps its existing limit; the
collection has a 600-second aggregate deadline to accommodate the serial phase.
Every module requires matching Case/Module/Harness/final OK markers, and errors
or overflows invalidate coverage. Sources and native dependency artifacts must
remain unchanged across the collection.

If a production gate fails, preserve its log and snapshot and run the collector
once with `--resume`. It performs at most one recheck of failed gates with the
same source, artifacts, samples, and limits, then collects the functional suite.
Its final verification records gate outcomes independently of functional
coverage; a failed recheck must not be presented as a passing gate.

## Recorded production results

The policy check reported zero findings and errors. Original scenario fixtures,
sample counts, and performance budgets were unchanged:

| Gate | First candidate p95 | Exact-snapshot recheck | Outcome |
| --- | --- | --- | --- |
| Relation projection | **5.213ms**, above 2ms budget | **389µs**, pass | Initial failure retained; one recheck passed |
| Membership | 18µs | Not repeated | Pass |
| Reachability closure | 83µs, 190 pairs | Not repeated | Pass |

The projection first-run median was 296µs. The reason for its timing spread is
not established here; the recheck is not evidence of uniform timing stability.
`gates.json`, `recheck-gates.json`, and the raw scenario logs retain both results.

The complete native suite passed in one invocation: **48 modules / 373 Cases**,
with Case, Module, Harness, and final OK markers checked independently of exit
status. It completed in 198.4 seconds. `suite-receipt.json`,
`suite-coverage.json`, and `modules/` retain the coverage evidence.

The collector's gate summary initially treated `recheck-` stage labels as
different gate names. This metadata bug was corrected after collection without
changing statuses, measurements, or source/native artifacts. The executed
collector and original summary are retained in `qualify-executed.py.txt` and
`verification-before-gate-label-fix.json`. `verification.json` records both
collector hashes and the gate-label normalization; the fixed `qualify.py` uses
the normalized names for future runs.

This qualification checks compatibility and the original performance gates.
It does not rerun the previous 19-profile, two-run paired comparison or establish
new build-latency claims for this ASP release.
