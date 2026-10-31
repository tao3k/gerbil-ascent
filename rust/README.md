# ASCENT Rust integration

ASCENT uses the original Scheme implementation through the pinned
`gerbil-scheme-rust` C ABI. The library build prepares its AOT module graph;
runtime Scheme DSL loading uses the native expander and evaluator without
launching gxi, gxc, gsc or Cargo. Program and result transport uses typed objects,
without JSON. Python calls the same library through PyO3.

Each Gambit VM has one owning OS thread. Scheme objects and roots stay on that
thread. Owned finite relational data can execute in Rust using Rayon, enabled by
default. The current upstream public Rust runtime admits one VM per process;
multiple caller threads do not create multiple VMs.

Rust Ascent is a dev-dependency for semantic comparison only. ASP Rust is also a
dev-dependency for repository checks.

## Validation

The [final local qualification report](../docs/performance/rust/qualification-hybrid-20261015-final.md)
records the full semantic corpus, installed-wheel checks and accepted isolated
36-configuration performance matrix, with source and executable identities.
The [native crash diagnosis](../docs/performance/rust/runtime-crash-20261015.md)
records the Ubuntu core, the matched upstream regression and the repaired SDK pin.

The public semantic corpus lives in `workbench/engine_tests`. Its `run_suite.py`
runner saves individual test outcomes, source digests, failures and timeouts.
Historical implementation and test records are local artifacts under
`.cache/ascent/rust-tests/history`;
they are not library components or an indication of completed support.

Cargo owns benchmark targets in each crate's `benches/` directory. Build the
hybrid target with `cargo bench --locked --manifest-path rust/Cargo.toml -p
ascent-scheme --bench hybrid_benchmark --no-run`. The independent workbench runs
matched measurements with `python3 -m ascent_workbench.benchmark_run_hybrid`. Accepted timings
require all builds and semantic checks to finish first. Results from runs with
concurrent build interference are diagnostic only.

The Rust Scheme evaluator has been removed. Modules, components, lexical
closures and `Value.apply` enter the original Scheme runtime. `open_session`
keeps native callbacks and explanations; `project_session` transfers an admitted
finite snapshot to Rust. `Engine.load_sources` selects the finite path when it
is available, with explicit Scheme/Rayon selection for matched tests. Opaque
objects and arbitrary callbacks remain in the VM.

Initial Scheme source occurrences are preserved, including duplicates; derived
relations retain set semantics. Numeric structural keys normalize representation
without changing exactness or inexact rounding. Checked provenance compares the
complete native answer with an independent replay, preserves multiplicity, and
revalidates source generation and current source content. Unsupported callbacks
return an explicit unsupported proof and never a positive verification result.

Cancellation covers admission queues, owner locks, native expansion and rule
execution. Source replacement has a final acceptance boundary before publishing
its generation. Cancellation and failure before that boundary retain the prior
committed source and result. Closing an engine revokes retained leases and
releases its native owner slots.

Wheel builds can repair external shared-library dependencies. Native DSL loading
still requires matching Gerbil SDK/syntax resources; the wheel is not a standalone
Gerbil SDK. Build-frozen source/resource digests are exposed by
`ascent.build.runtime_identity()` and checked by the consumer harness. Final
qualification and isolated benchmark receipts must be tied to the exact tested
artifact; the dated benchmark report records the observed results and limits.
