# Building the Python library

Build `python/pyproject.toml` with maturin, using the Gerbil SDK and the repository
package prefix (`GERBIL_HOME` and `GERBIL_PATH`). The Rust build delegates AOT
archive construction to the pinned `gerbil-scheme-rust` build library. Run
`maturin build --manifest-path rust/ascent-python/Cargo.toml --auditwheel repair`
from the repository root to repair external dynamic-library dependencies.

Install the resulting `gerbil-ascent` wheel and import `ascent`. Runtime DSL
loading does not run a compiler. Matching Gerbil syntax resources are required;
the wheel is not a standalone SDK. Inspect `ascent.build.runtime_identity()` for
the exact compiled inputs and runtime resource hashes. Consumer qualification
rejects resource or source drift.

Python uses the PyO3 extension directly. Rust owns execution, resource admission,
provenance checks and artifact publication. Rust Ascent remains a dev-dependency
for conformance tests. Rayon is enabled by default.
