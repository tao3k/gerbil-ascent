// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Finite interaction of generators, guards, bindings, negation and aggregation.

use super::common::scheme_output;
use ascent::aggregators::count;
use ascent::ascent;
use std::collections::BTreeSet;

type Edge = (u32, u32);

fn edges_for(mask: u32) -> Vec<Edge> {
    (0..3)
        .flat_map(|from| (0..3).map(move |to| (from, to)))
        .enumerate()
        .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(edge))
        .collect()
}

fn rust_rows(edges: &[Edge]) -> BTreeSet<String> {
    ascent! {
        relation edge(u32, u32);
        relation blocked(u32, u32);
        relation root(u32);
        relation candidate(u32, u32, u32);
        relation allowed(u32, u32);
        relation reach(u32, u32);
        relation reach_count(u32, usize);

        blocked(x, y) <-- edge(x, y), if (*x + *y) % 2 == 0;
        candidate(x, z, score) <-- edge(x, y),
            for z in [*y, (*y + 1) % 3], if *x != z,
            let score = *x + z;
        allowed(x, z) <-- candidate(x, z, _), !blocked(x, z);
        reach(x, z) <-- allowed(x, z);
        reach(x, z) <-- reach(x, y), allowed(y, z);
        reach_count(x, total) <-- root(x), agg total = count() in reach(x, _);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        root: vec![(0,), (1,), (2,)],
        ..AscentProgram::default()
    };
    program.run();
    program
        .blocked
        .iter()
        .map(|(x, y)| format!("blocked\t{x}\t{y}"))
        .chain(
            program
                .candidate
                .iter()
                .map(|(x, z, score)| format!("candidate\t{x}\t{z}\t{score}")),
        )
        .chain(
            program
                .allowed
                .iter()
                .map(|(x, z)| format!("allowed\t{x}\t{z}")),
        )
        .chain(
            program
                .reach
                .iter()
                .map(|(x, z)| format!("reach\t{x}\t{z}")),
        )
        .chain(
            program
                .reach_count
                .iter()
                .map(|(x, total)| format!("reach-count\t{x}\t{total}")),
        )
        .collect()
}

fn model_rows(edges: &[Edge]) -> BTreeSet<String> {
    let mut rows = BTreeSet::new();
    let blocked = edges
        .iter()
        .copied()
        .filter(|(x, y)| (x + y) % 2 == 0)
        .collect::<BTreeSet<_>>();
    for &(x, y) in &blocked {
        rows.insert(format!("blocked\t{x}\t{y}"));
    }
    let mut allowed = [[false; 3]; 3];
    for &(x, y) in edges {
        for z in [y, (y + 1) % 3] {
            if x != z {
                rows.insert(format!("candidate\t{x}\t{z}\t{}", x + z));
                if !blocked.contains(&(x, z)) {
                    allowed[x as usize][z as usize] = true;
                }
            }
        }
    }
    let mut reach = allowed;
    for (x, targets) in allowed.iter().enumerate() {
        for (z, present) in targets.iter().enumerate() {
            if *present {
                rows.insert(format!("allowed\t{x}\t{z}"));
            }
        }
    }
    // Floyd-Warshall is independent of the deductive engine's rule rounds.
    for via in 0..3 {
        for x in 0..3 {
            for z in 0..3 {
                reach[x][z] |= reach[x][via] && reach[via][z];
            }
        }
    }
    for (x, targets) in reach.iter().enumerate() {
        for (z, present) in targets.iter().enumerate() {
            if *present {
                rows.insert(format!("reach\t{x}\t{z}"));
            }
        }
        rows.insert(format!(
            "reach-count\t{x}\t{}",
            targets.iter().filter(|present| **present).count()
        ));
    }
    rows
}

#[test]
fn clause_composition_matches_rust_scheme_and_independent_model() {
    let mut cases = (0..512)
        .map(|mask| (mask, edges_for(mask)))
        .collect::<Vec<_>>();
    for (offset, mask) in [1, 3, 42, 73, 170, 255, 511].into_iter().enumerate() {
        let mut edges = edges_for(mask);
        edges.push(edges[0]);
        cases.push((512 + offset as u32, edges));
    }
    let request = format!(
        "({})\n",
        cases
            .iter()
            .map(|(case_id, edges)| {
                let edges = edges
                    .iter()
                    .map(|(x, y)| format!("({x} {y})"))
                    .collect::<Vec<_>>()
                    .join(" ");
                format!("({case_id} ({edges}))")
            })
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("clause-composition-rows", &request);
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    let scheme = scheme.into_iter().collect::<BTreeSet<_>>();
    let mut expected = BTreeSet::new();
    for (case_id, edges) in cases {
        let rust = rust_rows(&edges);
        let model = model_rows(&edges);
        assert_eq!(rust, model, "Rust case={case_id}");
        expected.extend(rust.into_iter().map(|row| format!("{case_id}\t{row}")));
    }
    assert_eq!(scheme, expected);
}
