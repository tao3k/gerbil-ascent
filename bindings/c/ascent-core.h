/* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later */
#ifndef ASCENT_CORE_H
#define ASCENT_CORE_H
#include "gerbil_scheme_owned.h"
#ifdef __cplusplus
extern "C" {
#endif
uint32_t ascent_core_abi_version(void);
/* Fixed Library Core Evidence owner. No Scheme VM or generic closure producer.
 * Captures: sources, constructor, workers, limits (input/derived/output), optional
 * diagnostics Boolean (default false; timing is observation, not authority).
 * Alternatively replace sources with components and entry. Each component has
 * id, source, exports (null or names), dependencies (component and bindings).
 * The existing Core linker checks scope, visibility and dependency cycles;
 * source and component captures are mutually exclusive, never fallback paths.
 * Precompiled Graph captures instead use graph, workers, limits, diagnostics:
 * graph fields are algorithm, source, width, rows, output, captures. Algorithms
 * projection (captures.columns) and transitive (empty captures) call the existing
 * maintenance-generated Graph closures. The retained session owns resulting
 * graph state; replace withdraws and recomputes using the existing Core.
 * This is not an arbitrary procedure/closure compiler or an eval interface.
 * Call methods: runtime/diagnose/describe/run/replace/explain/rows/release-result.
 * Callback results use {ok: bool, value: ...} or {ok: false, error: text}.
 * run accepts explicit resultFormat="graph" (default) or "typed-rows".
 * Typed rows preserve exact scalars and full graph/namespace observations for
 * complex cells; invalid formats fail, never fall back. Native fact limits count
 * all actual rows independently of transport shape.
 * Domain failure is independent of C transport status. The owned header's
 * pointer, owner-thread, immutable-result and exact-once release contracts apply.
 * All named methods call existing Core operations, never a second evaluator. */
int32_t ascent_core_open(const GerbilOwnedView *, GerbilOwnedCallable *);
/* Fixed compressed reachability owner. Empty captures; no Scheme VM.
 * Methods: insert(edge,budget), freeze, resources, validate, close-state;
 * cuts: rows(cut,columns,key,limit), contains(cut,row), cut-resources,
 * release-cut. Cut identities are owner-local and never runtime pointers.
 * Closing mutable state retains admitted immutable cuts until release. */
int32_t ascent_reachability_open(const GerbilOwnedView *, GerbilOwnedCallable *);
#ifdef __cplusplus
}
#endif
#endif
