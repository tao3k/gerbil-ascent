// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Bounded arity, repeated-variable, self-loop and rule-order differential.

use super::common::scheme_output;
use ascent::ascent;
use std::collections::BTreeSet;

type Edge = (u32, u32);
const EDGES: [Edge; 6] = [(0, 0), (0, 1), (1, 1), (1, 2), (2, 0), (2, 2)];

fn edges_for(mask: u32) -> Vec<Edge> {
    EDGES
        .iter()
        .enumerate()
        .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(*edge))
        .collect()
}

// Ascent 0.8.0 expands zero-arity relations into unused local `tuple`
// bindings. Keep the lint scoped to this pinned-macro oracle; `expect` will
// fail the gate when the upstream expansion stops emitting those bindings.
#[expect(unused_variables, reason = "Ascent 0.8.0 zero-arity macro expansion")]
fn rust_rows(edges: &[Edge], enabled: bool, variant: u32) -> BTreeSet<String> {
    macro_rules! collect {
        ($program:expr) => {{
            let program = $program;
            let mut rows = BTreeSet::new();
            rows.extend(
                program
                    .loop_node
                    .iter()
                    .map(|(x,)| format!("loop_node\t{x}")),
            );
            rows.extend(
                program
                    .wedge
                    .iter()
                    .map(|(x, y, z)| format!("wedge\t{x}\t{y}\t{z}")),
            );
            rows.extend(
                program
                    .quad
                    .iter()
                    .map(|(x, y, z, w)| format!("quad\t{x}\t{y}\t{z}\t{w}")),
            );
            rows.extend(
                program
                    .reach
                    .iter()
                    .map(|(x, y)| format!("reach\t{x}\t{y}")),
            );
            if !program.cycle0.is_empty() {
                rows.insert("cycle0".to_owned());
            }
            rows
        }};
    }
    if variant == 0 {
        ascent! {
            relation enabled();
            relation edge(u32, u32);
            relation loop_node(u32);
            relation wedge(u32, u32, u32);
            relation quad(u32, u32, u32, u32);
            relation reach(u32, u32);
            relation cycle0();
            loop_node(x) <-- edge(x, x);
            wedge(x, y, z) <-- enabled(), edge(x, y), edge(y, z);
            quad(x, y, z, w) <-- wedge(x, y, z), edge(z, w);
            reach(x, y) <-- edge(x, y);
            reach(x, z) <-- reach(x, y), edge(y, z);
            cycle0() <-- reach(x, x);
        }
        let mut program = AscentProgram {
            enabled: if enabled { vec![()] } else { vec![] },
            edge: edges.to_vec(),
            ..AscentProgram::default()
        };
        program.run();
        collect!(program)
    } else {
        ascent! {
            relation enabled();
            relation edge(u32, u32);
            relation loop_node(u32);
            relation wedge(u32, u32, u32);
            relation quad(u32, u32, u32, u32);
            relation reach(u32, u32);
            relation cycle0();
            cycle0() <-- reach(x, x);
            reach(x, z) <-- edge(y, z), reach(x, y);
            reach(x, y) <-- edge(x, y);
            quad(x, y, z, w) <-- edge(z, w), wedge(x, y, z);
            wedge(x, y, z) <-- edge(y, z), edge(x, y), enabled();
            loop_node(x) <-- edge(x, x);
        }
        let mut program = AscentProgram {
            enabled: if enabled { vec![()] } else { vec![] },
            edge: edges.to_vec(),
            ..AscentProgram::default()
        };
        program.run();
        collect!(program)
    }
}

fn model_rows(edges: &[Edge], enabled: bool) -> BTreeSet<String> {
    let mut rows = BTreeSet::new();
    for &(from, to) in edges {
        if from == to {
            rows.insert(format!("loop_node\t{from}"));
        }
    }
    if enabled {
        for &(from, via) in edges {
            for &(start, to) in edges {
                if via == start {
                    rows.insert(format!("wedge\t{from}\t{via}\t{to}"));
                    for &(next, last) in edges {
                        if to == next {
                            rows.insert(format!("quad\t{from}\t{via}\t{to}\t{last}"));
                        }
                    }
                }
            }
        }
    }
    // Floyd-Warshall is independent of the rule engine's semi-naive rounds.
    let mut reach = [[false; 3]; 3];
    for &(from, to) in edges {
        reach[from as usize][to as usize] = true;
    }
    for via in 0..3 {
        for from in 0..3 {
            for to in 0..3 {
                reach[from][to] |= reach[from][via] && reach[via][to];
            }
        }
    }
    for (from, targets) in reach.iter().enumerate() {
        for (to, reachable) in targets.iter().enumerate() {
            if *reachable {
                rows.insert(format!("reach\t{from}\t{to}"));
                if from == to {
                    rows.insert("cycle0".to_owned());
                }
            }
        }
    }
    rows
}

#[test]
fn arities_repeated_variables_and_self_loops_match_model_in_both_rule_orders() {
    let request = format!(
        "({})\n",
        (0..64)
            .map(|mask| {
                let edges = edges_for(mask)
                    .into_iter()
                    .map(|(from, to)| format!("({from} {to})"))
                    .collect::<Vec<_>>()
                    .join(" ");
                format!("({mask} ({edges}))")
            })
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("arity-repetition-rows", &request);
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    let scheme = scheme.into_iter().collect::<BTreeSet<_>>();
    let mut expected = BTreeSet::new();
    for mask in 0..64 {
        let edges = edges_for(mask);
        for enabled in [false, true] {
            let model = model_rows(&edges, enabled);
            for variant in 0..2 {
                let rust = rust_rows(&edges, enabled, variant);
                assert_eq!(
                    rust, model,
                    "Rust mask={mask} enabled={enabled} variant={variant}"
                );
                expected.extend(
                    rust.into_iter()
                        .map(|row| format!("{mask}\t{}\t{variant}\t{row}", u8::from(enabled))),
                );
            }
        }
    }
    assert_eq!(scheme, expected);
}
