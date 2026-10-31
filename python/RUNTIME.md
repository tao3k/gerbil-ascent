# Scheme DSL through Rust/PyO3

The library build prepares the original Scheme ASCENT module graph with the
pinned `gerbil-scheme-rust` AOT builder. At runtime, the C ABI transfers typed
Scheme/Rust values. Python imports `ascent`, provided by PyO3. There is no Python
CFFI extension or JSON program/result boundary.

`Engine.dsl(source, trusted=True)` loads the original Scheme DSL, including
modules, lexical closures and components. `Module.call` and `Value.apply` execute
on the VM owner thread. Complex values preserve their type, identity and sharing;
opaque objects remain in that VM. Native references are scoped to their owner.
Loading DSL does not launch a compiler or Scheme subprocess.

`Engine.read_rules` is the separate inert rule-source reader. It admits its
finite declaration subset without granting permission to execute host code.
`Engine.load_sources` transfers an admissible finite snapshot to owned Rust data.
Rayon is enabled by default. Explicit Scheme/Rayon backend selection supports
matched semantic and performance checks. Module constructors expose
`open_session` for full native semantics and `project_session` for an admitted
owned finite snapshot. Arbitrary callbacks stay in the VM.

Each VM has one owning OS thread. The current upstream public runtime admits one
VM per process. Rayon threads only access Rust-owned data and do not enter the
Gambit VM concurrently.

Cancellation and resource limits apply to admission, native execution and owned
execution. Replacement commits only after final acceptance; earlier failure
retains the previous generation. Initial source occurrences count even when they
duplicate a row. Derived relations retain set semantics.

Checked provenance binds source identity, generation, content and checker
version. Native answers must match an independent finite replay, including
multiplicity. Mutable-source changes revoke verification. Unsupported host
callbacks yield an explicit unsupported proof, never a successful verification.
Historical explanations remain readable after replacement, with currentness
reported separately; closing their engine revokes ownership.

A wheel requires matching Gerbil syntax resources. It does not include a complete
SDK. `ascent.build.runtime_identity()` exposes the compiled source and runtime
resource hashes; the consumer harness rejects drift. See [building](BUILDING.md)
and the [runtime contract](../rust/README.md).

The Rust execution pool accepts `work_distribution="adaptive"` (default),
`"across-requests"`, or `"within-request"` in `Engine` and `ProcessPool.engine`.
These select Rust-owned evaluation fanout without changing the requested worker
count or moving a Scheme lease between VM processes. Adaptive fanout is disabled
when that engine observes at least as many queued/running uncached evaluations
as pool workers. Across-request
execution leaves each evaluation on one worker; it is not a priority scheduler.
Within-request execution permits nested parallel joins under shared load.
Cancellation, exact work/fact limits and failed-publication semantics are the
same in every mode. Cloned Rust engines share the population ledger; separately
constructed engines do not share that ledger even when given the same pool.
This option does not activate gerbil-scheme-rust's in-process native-owner router
inside ASCENT's exec-isolated process pool. The two ownership paths are distinct.
