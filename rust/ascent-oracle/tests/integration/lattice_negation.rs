// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! A lattice fixed point feeds a later negative stratum across source phases.

use super::common::scheme_output;
use ascent::{Dual, ascent};

type Edge = (u32, u32, u32);
type Case = (Vec<Edge>, Vec<Edge>);

fn cases() -> Vec<Case> {
    let candidates = [
        (0, 1, 4),
        (0, 2, 1),
        (2, 1, 1),
        (1, 2, 3),
        (1, 3, 1),
        (2, 3, 2),
    ];
    let mut result: Vec<Case> = (0..64u32)
        .map(|mask| {
            let mut initial = Vec::new();
            let mut added = Vec::new();
            for (bit, edge) in candidates.into_iter().enumerate() {
                if mask & (1 << bit) != 0 {
                    if bit % 2 == 0 {
                        initial.push(edge);
                    } else {
                        added.push(edge);
                    }
                }
            }
            (initial, added)
        })
        .collect();
    result.push((vec![(0, 1, 4), (2, 1, 1)], vec![(0, 2, 1), (0, 2, 1)]));
    result.push((vec![(2, 1, 1), (0, 1, 4)], vec![(2, 3, 2), (0, 2, 1)]));
    result
}

fn model_rows(edges: &[Edge]) -> Vec<String> {
    let mut distance = [None; 4];
    distance[0] = Some(0u32);
    for _ in 0..4 {
        let mut changed = false;
        for &(from, to, weight) in edges {
            if let Some(source) = distance[from as usize] {
                let candidate = source + weight;
                let target = &mut distance[to as usize];
                if target.is_none_or(|prior| candidate < prior) {
                    *target = Some(candidate);
                    changed = true;
                }
            }
        }
        if !changed {
            break;
        }
    }
    let mut rows = Vec::new();
    for (node, value) in distance.into_iter().enumerate() {
        if let Some(value) = value {
            rows.push(format!("score\t{node}\t{value}"));
            if value <= 2 {
                rows.push(format!("cheap\t{node}"));
            } else {
                rows.push(format!("not-cheap\t{node}"));
            }
        } else {
            rows.push(format!("not-cheap\t{node}"));
        }
    }
    rows.sort_unstable();
    rows
}

fn rust_rows(edges: &[Edge]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32, u32);
        relation origin(u32);
        relation root(u32);
        lattice score(u32, Dual<u32>);
        relation cheap(u32);
        relation not_cheap(u32);

        score(node, Dual(0)) <-- origin(node);
        score(to, Dual(distance + weight)) <--
            score(from, ?Dual(distance)), edge(from, to, weight);
        cheap(node) <-- score(node, ?Dual(distance)), if *distance <= 2;
        not_cheap(node) <-- root(node), !cheap(node);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        origin: vec![(0,)],
        root: vec![(0,), (1,), (2,), (3,)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .score
            .iter()
            .map(|(node, Dual(distance))| format!("score\t{node}\t{distance}")),
    );
    rows.extend(program.cheap.iter().map(|(node,)| format!("cheap\t{node}")));
    rows.extend(
        program
            .not_cheap
            .iter()
            .map(|(node,)| format!("not-cheap\t{node}")),
    );
    rows.sort_unstable();
    rows
}

fn render_edges(edges: &[Edge]) -> String {
    edges
        .iter()
        .map(|(from, to, weight)| format!("({from} {to} {weight})"))
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn lattice_refinement_feeds_negative_stratum_across_updates() {
    let cases = cases();
    assert_eq!(cases.len(), 66);
    let request = format!(
        "({})\n",
        cases
            .iter()
            .map(|(initial, added)| {
                format!("(({}) ({}))", render_edges(initial), render_edges(added))
            })
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("lattice-negation-rows", &request);
    let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    actual.sort_unstable();

    let mut expected = Vec::new();
    for (index, (initial, added)) in cases.iter().enumerate() {
        let mut union = initial.clone();
        union.extend_from_slice(added);
        for (phase, edges) in [initial.as_slice(), union.as_slice(), initial.as_slice()]
            .into_iter()
            .enumerate()
        {
            let rows = rust_rows(edges);
            assert_eq!(rows, model_rows(edges), "case {index}, phase {phase}");
            expected.extend(
                rows.into_iter()
                    .map(|row| format!("{index}\t{phase}\t{row}")),
            );
        }
    }
    expected.sort_unstable();
    assert_eq!(actual, expected);
}
