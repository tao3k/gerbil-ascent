// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Three-relation SCC over all loop-free three-node graphs and two rule orders.

use super::common::scheme_output;
use ascent::ascent;

const CANDIDATE_EDGES: [(u32, u32); 6] = [(0, 1), (0, 2), (1, 0), (1, 2), (2, 0), (2, 1)];

fn edges_for_mask(mask: u32) -> Vec<(u32, u32)> {
    CANDIDATE_EDGES
        .into_iter()
        .enumerate()
        .filter_map(|(index, edge)| (mask & (1 << index) != 0).then_some(edge))
        .collect()
}

fn rust_rows(mask: u32, edges: &[(u32, u32)], variant: u32) -> Vec<String> {
    macro_rules! collect_rows {
        ($program:expr) => {{
            let program = $program;
            let mut rows = Vec::new();
            for (name, relation) in [("a", &program.a), ("b", &program.b), ("c", &program.c)] {
                rows.extend(
                    relation
                        .iter()
                        .map(|(from, to)| format!("{mask}\t{variant}\t{name}\t{from}\t{to}")),
                );
            }
            rows
        }};
    }

    if variant == 0 {
        ascent! {
            relation edge(u32, u32);
            relation a(u32, u32);
            relation b(u32, u32);
            relation c(u32, u32);
            b(x, z) <-- a(x, y), edge(y, z);
            c(x, z), a(x, z) <-- b(x, y), edge(y, z);
            b(x, y) <-- c(x, y);
            a(x, y) <-- edge(x, y);
        }
        let mut program = AscentProgram {
            edge: edges.to_vec(),
            ..AscentProgram::default()
        };
        program.run();
        collect_rows!(program)
    } else {
        ascent! {
            relation edge(u32, u32);
            relation a(u32, u32);
            relation b(u32, u32);
            relation c(u32, u32);
            a(x, y) <-- edge(x, y);
            b(x, y) <-- c(x, y);
            c(x, z), a(x, z) <-- edge(y, z), b(x, y);
            b(x, z) <-- edge(y, z), a(x, y);
        }
        let mut program = AscentProgram {
            edge: edges.to_vec(),
            ..AscentProgram::default()
        };
        program.run();
        collect_rows!(program)
    }
}

#[test]
fn three_relation_scc_and_clause_orders_match_ascent() {
    let masks: Vec<_> = (0..64).collect();
    let request = format!(
        "({})\n",
        masks
            .iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("scc-order-rows", &request);
    let mut scheme: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(scheme.pop().as_deref(), Some("END"));

    let mut rust = Vec::new();
    for mask in masks {
        let edges = edges_for_mask(mask);
        let first = rust_rows(mask, &edges, 0);
        let second = rust_rows(mask, &edges, 1);
        let normalize = |rows: Vec<String>| {
            rows.into_iter()
                .map(|row| row.split_once('\t').expect("case prefix").1.to_owned())
                .map(|row| row.split_once('\t').expect("variant prefix").1.to_owned())
                .collect::<Vec<_>>()
        };
        let mut first_normalized = normalize(first.clone());
        let mut second_normalized = normalize(second.clone());
        first_normalized.sort_unstable();
        second_normalized.sort_unstable();
        assert_eq!(first_normalized, second_normalized, "graph mask {mask}");
        rust.extend(first);
        rust.extend(second);
    }
    rust.sort_unstable();
    scheme.sort_unstable();
    assert_eq!(scheme, rust);
}
