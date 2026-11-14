# Git-pinned Python publication

The Rust workspace consumes all gerbil-scheme-rust packages from one explicit
Git revision, including the shared Python ABI and build-side IR generator.
There is no cross-repository path dependency or adjacent-checkout fallback.
Internal ASCENT workspace paths remain ordinary monorepo dependencies.

During maintenance builds, `build_source_root` identifies the Cargo dependency
tree that actually compiled the bridge. ASCENT freezes the declared complete
source trees, headers, manifests and lockfiles into its wheel with per-path SHA
checks. The installed package does not use that build path, a Scheme VM or SDK.
Build-time Scheme algorithm generation remains separate from runtime Evidence
declaration loading and existing Core C ABI execution.

`asp-rust` is test-only. Its workspace version declaration is inherited solely
through `[dev-dependencies]`; it is not a wheel normal/build dependency.

Publication qualification must distinguish the published ASCENT revision,
bridge revision, wheel bytes, installed extension and complete source inventory.
An installation's Git provenance must come from the installer, never a patched
`direct_url.json`. Git publication alone does not admit a wheel or consumer run.

Raw process JSON, stdout/stderr, benchmark samples and graph bundles stay local.
Git records source, contracts and concise qualification summaries, not raw runs.
Keep failed/stale/timeout observations locally and never change their identities
to fit a new candidate. Complete consumer, sealed review, current graph and
matched performance acceptance remain separate gates with unchanged budgets.

Runtime release code keeps O3 and thin LTO; maintenance build dependencies also
use O3. Compilation elapsed time is not query latency. Observe real completed
compiler artifacts to distinguish continued compilation from a stalled build,
never synthetic heartbeat messages. This build-progress policy does not extend
consumer, sealed-review, graph or performance execution budgets. Both publication
build and execution acceptance must be qualified independently; a warmed build
cache is not a cold-build claim.
