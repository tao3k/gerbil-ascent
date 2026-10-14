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

The public semantic corpus lives in `workbench/engine_tests`. Its `run_suite.py`
runner saves individual test outcomes, source digests, failures and timeouts.
Historical implementation and test records are retained under `tests/history`;
they are not library components or an indication of completed support.

The matched performance harness is `benchmarks/run-hybrid.py`. Accepted timings
require all builds and semantic checks to finish first. Results from runs with
concurrent build interference are diagnostic only.

The public interface conversion is incomplete: native rejection handling,
result ownership, resource admission, packaging and the full semantic corpus
must pass before claiming complete support. The previous Rust Scheme evaluator
has not yet been retired. Current native wheels still require the configured
Gerbil SDK and syntax resources; they are not yet self-contained distributions.
