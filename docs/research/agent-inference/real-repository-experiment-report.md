<!-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors -->
<!-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later -->

# Real Repository Reasoning Experiment

## Objective and experiment status

Measure cumulative provider-reported thinking tokens until the first independently accepted implementation, including source exploration, rejected changes, failed submissions and repair. Visible answer length is not the savings denominator.

Status: **completed**. Two source-qualified tasks, three conditions, two repetitions: 12 trajectories. The frozen primary budget was 10 turns. Every unfinished primary trajectory is eligible for the same adaptive continuation to 40 cumulative turns. Primary and adaptive outcomes are reported separately. Prior history, opaque provider reasoning, patches and token charges are retained.

## Complete task statements

### group-centrality-order

Repair group_betweenness_centrality: on a directed graph, permuting the same group members can change its value. A path 0->1->2->3->4, a disjoint path 6->7->8->9->10, and additional edges 3->2->1 give different results for [1,3,7,9] and [9,7,3,1] with normalized=False. The result must be independent of group ordering. Preserve directed and undirected behavior, weighted shortest paths, endpoint inclusion, normalization, and disconnected-component handling. Diagnose the interaction among shortest-path counts and accumulated group contributions; repair the implementation without replacing it with a hard-coded answer.

Editable implementation: networkx/algorithms/centrality/group.py.

### series-root-precision

Repair rs_nth_root for inputs whose leading exponent is nonzero. For p=x+x**2, rs_nth_root(p,-1,x,3) drops x-x**2 whereas rs_series_inversion preserves those terms. For p=x**4+x**5, the square root at precision 3 returns zero instead of x**2. Precision excludes terms at or above the requested exponent. Handle reciprocal and positive fractional roots, rational exponents, multivariate coefficients and precision boundaries consistently; preserve existing series inversion and root behavior. Trace normalization, recursive expansion and leading-power restoration before repairing the general case.

Editable implementation: sympy/polys/ring_series.py, sympy/polys/puiseux.py.

## Design and independent acceptance

Sources: [NetworkX PR 8931](https://github.com/networkx/networkx/pull/8931), first public disclosure September 27, 2026; [SymPy issue 30698](https://github.com/sympy/sympy/issues/30698), first public disclosure October 8, 2026. Exact source/grader/environment hashes are bound in the source audit and frozen plan. Recent disclosure does not prove absence from training or retrieval.

The model sees the complete problem, parent source, automatic source/edit/execution tools and development controls. It does not receive the solution diff, fixed implementation, hidden assertions or git/network access. Output ceiling: 131,072 tokens; high reasoning effort; automatic tool choice. The requested backend alias is `deepseek-flash`; the returned alias does not attest an immutable model revision.

Ordinary tools expose source and execution observations. Scheme fresh and Scheme retained additionally expose identical least-fixed-point support over local syntactic references. Only retained evidence persists across queries. Because fresh and retained return identical facts and complete model history, cache persistence alone has no designed mechanism to reduce model thinking; their token differences are stochastic observations, not causal evidence of a cache-driven thinking benefit. Compare either Scheme condition with ordinary tools for the syntactic-support intervention, and fresh versus retained for checker reuse. Source-byte changes invalidate evidence. This is checked syntactic support, not proof of Python execution or a general semantic evidence engine. Continuation reconstructs source/evidence state from original tool actions; reconstruction work is separate, and no historical model or test requests are repeated.

Acceptance requires exact hidden test identities, exit zero and all cases passing: 24 NetworkX cases and 3 SymPy cases. Qualification had 2 failing and 22 passing NetworkX cases, and 2 failing and 1 passing SymPy cases. These 27 selected cases do not constitute full upstream CI. The tool adapter restricts edits and import changes; this is a bounded repair pilot.

## Primary 10-turn outcomes

| Condition | Verified / trajectories | Thinking tokens consumed, including censored work |
| --- | ---: | ---: |
| ordinary-tools | 0/4 | 25,924 |
| scheme-fresh | 0/4 | 25,737 |
| scheme-retained | 0/4 | 34,939 |

## Cumulative outcomes including uniform continuation

| Task | Rep | Condition | Status | Calls | Thinking tokens | Repair thinking / peak USD | Evidence queries / reused components |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: |
| group-centrality-order | 1 | ordinary-tools | censored | 40 | 53,282 | 0 / 0.000000 | 0 / 0 |
| group-centrality-order | 1 | scheme-fresh | verified | 34 | 57,987 | 37,824 / 0.068536 | 6 / 0 |
| group-centrality-order | 1 | scheme-retained | censored | 40 | 45,453 | 0 / 0.000000 | 8 / 3 |
| group-centrality-order | 2 | ordinary-tools | verified | 20 | 55,276 | 0 / 0.000000 | 0 / 0 |
| group-centrality-order | 2 | scheme-fresh | verified | 24 | 35,230 | 0 / 0.000000 | 6 / 0 |
| group-centrality-order | 2 | scheme-retained | verified | 26 | 40,092 | 7,653 / 0.013650 | 5 / 2 |
| series-root-precision | 1 | ordinary-tools | verified | 38 | 60,583 | 0 / 0.000000 | 0 / 0 |
| series-root-precision | 1 | scheme-fresh | verified | 36 | 65,327 | 0 / 0.000000 | 15 / 0 |
| series-root-precision | 1 | scheme-retained | verified | 30 | 31,144 | 0 / 0.000000 | 10 / 8 |
| series-root-precision | 2 | ordinary-tools | verified | 40 | 54,626 | 0 / 0.000000 | 0 / 0 |
| series-root-precision | 2 | scheme-fresh | verified | 27 | 46,140 | 0 / 0.000000 | 13 / 0 |
| series-root-precision | 2 | scheme-retained | censored | 40 | 73,328 | 0 / 0.000000 | 19 / 16 |

| Condition | Independently verified / trajectories | Total thinking consumed including censored work |
| --- | ---: | ---: |
| ordinary-tools | 3/4 | 223,767 |
| scheme-fresh | 4/4 | 204,684 |
| scheme-retained | 2/4 | 190,017 |

Repair work starts at the first failing development check or independently rejected submission and includes that provider turn through acceptance or censoring. Provider usage cannot be apportioned among individual actions within one turn. Source-edit rejections and diagnostic calls are still charged in total effort. Zero repair thinking means no failing validation feedback was observed before termination; it does not mean a censored trajectory did no wasted work.

## Paired thinking reductions

- scheme-fresh: 3 jointly accepted pairs; token-weighted reduction **13.95%**. Censored trajectories are excluded from this ratio and remain visible above.
- scheme-retained: 2 jointly accepted pairs; token-weighted reduction **38.51%**. Censored trajectories are excluded from this ratio and remain visible above.

### Integrated outcome

- ordinary-tools: 3/4 independently verified; 138 cumulative calls; 223,767 thinking tokens including censored work.
- scheme-fresh: 4/4 independently verified; 121 cumulative calls; 204,684 thinking tokens including censored work.
- scheme-retained: 2/4 independently verified; 136 cumulative calls; 190,017 thinking tokens including censored work.

The retained condition must not be promoted as a stable 40–50% improvement: its jointly accepted-pair ratio omits visibly censored trajectories, and its acceptance rate must be considered alongside that ratio. This pilot validates an executable measurement path and real checked-component reuse, with mixed quality and thinking outcomes.

### Mechanism reflection

The current Scheme intervention checks syntactic dependency closure. It does not encode the domain invariants that determine matrix-update correctness or leading-exponent precision. Consequently, cache reuse is real checker work reuse but does not establish semantic enhancement of model thinking. The next integrated intervention needs source-qualified executable observations and domain claims checked by the appropriate Scheme or external checker, explicit invalidation when premises change, and a new independent matched corpus. The model should continue reasoning about the complete problem; a mandatory subproblem-first workflow would change the hypothesis. Lean/Quint must model the observation and invalidation contract, rather than certify arbitrary model reasoning text.

## Research expense and execution fault

| Category | Started requests | Responses with usage | Thinking tokens | Peak USD estimate | Off-peak USD estimate | Unknown usage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| invalidExecution | 65 | 64 | 62,152 | 0.111276 | 0.055638 | 1 |
| primary | 120 | 120 | 86,600 | 0.195363 | 0.097682 | 0 |
| continuation | 249 | 249 | 498,351 | 0.800080 | 0.400040 | 0 |
| responsePreservingRecovery | 26 | 26 | 33,517 | 0.069544 | 0.034772 | 0 |

Known research expense: **$1.176264 at peak rates / $0.588132 at off-peak rates**, plus 1 request(s) without final usage. No unknown charge is treated as zero.

The initial paid run had a local relative-path defect: the child changed its working directory and could not find its sandbox profile. Those calls are research expense, excluded from model accuracy and savings claims. One interrupted request has no final usage receipt; its charge is unknown, not zero. Paths are now normalized and execution failures stop further paid calls. Separately, the embedded Gambit SIGCHLD handler could reap Python-owned child exit statuses; restoring Python ownership is covered by a regression requiring exits 7, 0 and 9 to survive engine initialization. Near the end of continuation, an idle worker queue raised BlockingIOError and broke the process pool. A separate diagnosis reproduced runtime changes to standard descriptor flags, including nonblocking mode; host descriptor flags are now preserved around C ABI calls, and future workers run one trajectory each. The last fully receipted response was recovered without another paid request, its missing tool output completed, and its full history continued serially for `series-root-precision`, repetition 2, `scheme-retained`. The recovery manifest explicitly binds the infrastructure changes; original receipts remain unchanged. Descriptor changes are observed; the complete internal causal path to the queue failure is not formally established.

Estimates use reported cached input and output including thinking. [Official DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing/) lists peak rates of $0.30/M uncached input, $0.006/M cached input and $1.20/M output, with off-peak rates half as large. These are tariff estimates, not verified account debits. Total research expense includes all categories and any unknown charge remains unresolved.

## Interpretation and remaining scope

No 40–50% improvement is asserted without jointly accepted comparisons. Two tasks and two repetitions per condition cannot establish broad four-family performance or statistical significance. Source restrictions, partial syntactic extraction and selected grader coverage limit generalization. Exact-repeat zero-call reuse is a separate experiment and is not included in first-solution improvement. Existing Lean/Quint retention results do not prove this collector, Python extractor or evaluator isolation; no new formal closure is claimed.

The source-selection protocol follows [SWE-rebench](https://arxiv.org/html/2505.20411v2), [SWE-rebench V2](https://arxiv.org/html/2602.23866v2) and [LiveCodeBench](https://arxiv.org/abs/2403.07974): fresh provenance, executable failure-to-pass qualification, hidden grading and repeated trajectories. Negative results and local infrastructure faults remain part of the record.
