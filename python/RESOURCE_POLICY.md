# Caller-Owned Cardinality And Transport Policy

ASCENT is a native Library for Agentic AI. Its ordinary Program constructor,
`ascent` form, operator compiler, operator reference evaluation and positive
insertion plans now default to unlimited fact/row counts (`+inf.0` in Scheme).
This is not a large replacement integer. Existing explicit finite DSL bounds
are retained. Infinity is reported as `"unlimited"`, never non-standard JSON.

Python callers can impose native ceilings without parsing or rewriting DSL:

```python
from ascent_engine import Engine, FactLimits

source = """
(define-evidence (make-events)
  (gerbil-ascent-program
    (list (gerbil-ascent-relation 'event 1 [])) []
    +inf.0 +inf.0 +inf.0 '(event)))
"""

engine = Engine()  # No request-byte ceiling by default.
with engine.evidence(source, "make-events", trusted=True) as session:
    assert session.fact_limits["input"] == "unlimited"
    session.run(queries=[])  # Complete initial session before replacing sources.
    session.replace({"event": [[1], [2]]})
    result = session.run(queries=["event"])

with engine.evidence(source, "make-events", trusted=True,
                     limits=FactLimits(input=1000, derived=5000, output=6000)) as session:
    pass
engine.shutdown()
```

`None` fields mean no caller ceiling. Native Scheme validates positive exact
integers and enforces total source occurrences, derived facts and materialized
output, not merely per-relation unique rows. Caller limits may tighten explicit
DSL declarations, never loosen them. The native session's `fact_limits` receipt
reports effective limits. Ceilings are available on `Engine.open`, `open_sources`,
`open_module`, `evidence` and the existing `EvidenceStore`/`EvidenceChain` wrappers.
Retained-session identities include the caller count policy.

Request bytes are a separate transport policy. `Engine(max_request_bytes=...)`
checks the exact UTF-8 JSON request length; the default `None` has no ceiling.
The ABI retains allocation-overflow, UTF-8 and NUL validation. Trusted host code
can still exhaust memory. This interface is not a sandbox or an authorization
mechanism, and an unlimited count does not guarantee termination or completion.

Independent structural and lifecycle constraints remain: DSL source/form/tree
bounds, native scope/session/value limits, symbol codec constraints and native
graph projection limits. A projection failure retains native results; it must
not reduce executable semantics. Runtime deadlines and host watchdogs are
independent of cardinality. Cooperative run deadlines do not preempt arbitrary
Scheme callbacks or qualify every admission/extraction phase.

Consumers import Python only and supply ordinary DSL definitions. Scheme module
imports, hygienic expansion, inference, aggregation, lattice and incremental
state remain in the Library. Maintenance builds belong to Library `build.ss` /
`defbuild-script` / upstream `std/make`, not a downstream compilation workflow.
