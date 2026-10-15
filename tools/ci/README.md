# CI execution

`scheme`, `rust-pyo3`, and the three Rust Ascent differential shards start
independently. `scheme` retains the full original Scheme tests, performance
contracts, source-view checks, retained-session checks, and crash diagnostics.

`rust-pyo3` prepares the pinned Gerbil SDK and Scheme library, then runs the
complete Rust workspace tests, strict Clippy, wheel construction, and the
original Python interface semantics. These have separate step timings. Rust
and PyO3 share one Cargo target directory, Gerbil environment, Python interpreter,
and equivalent production feature selection. Rust Ascent remains a dev-dependency.

The Cargo cache is scoped by OS/architecture, Rust/Python compiler identity,
Gerbil/C compiler identity, lockfile, and source/configuration digests. Restore
fallbacks stay within the same toolchain, SDK and lockfile. Cargo invalidation
and the runtime's source/artifact checks still run; cached outputs are not
qualification evidence and never skip tests.

`formal` waits for `rust-pyo3` to publish its exact wheel and matching runtime
syntax resources. It retains Lean, Quint, conformance comparisons, and the
independent installed-wheel Python package and workbench tests. The required
`native-and-oracle` aggregate admits success only when Scheme, Rust/PyO3,
every differential shard, and formal all succeed.

The split removes Scheme validation from the Rust producer's serial dependency
chain. It does not remove the compiler's work. Cold and warm cache timings must
be reported separately and bound to the tested commit.
