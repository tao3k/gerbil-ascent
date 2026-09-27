// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Exhaustive small-graph differential for interacting Ascent features.

use super::common::scheme_output;
use std::cmp::Ordering;

use ascent::{aggregators::count, ascent, lattice::Lattice};

type Edge = (u32, u32);
type Case = (Vec<Edge>, Vec<u32>);

// Ascent 0.8.0's public Product<T> lacks Hash, which its lattice storage
// requires. This newtype uses the same coordinatewise product order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct CoordinateMax(u32, u32);

impl PartialOrd for CoordinateMax {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        match (self.0.cmp(&other.0), self.1.cmp(&other.1)) {
            (Ordering::Equal, axis) | (axis, Ordering::Equal) => Some(axis),
            (Ordering::Less, Ordering::Less) => Some(Ordering::Less),
            (Ordering::Greater, Ordering::Greater) => Some(Ordering::Greater),
            _ => None,
        }
    }
}

impl Lattice for CoordinateMax {
    fn meet_mut(&mut self, other: Self) -> bool {
        let joined = Self(self.0.min(other.0), self.1.min(other.1));
        let changed = *self != joined;
        *self = joined;
        changed
    }

    fn join_mut(&mut self, other: Self) -> bool {
        let joined = Self(self.0.max(other.0), self.1.max(other.1));
        let changed = *self != joined;
        *self = joined;
        changed
    }
}

fn cases() -> Vec<Case> {
    let mut result = Vec::with_capacity(522);
    for mask in 0..(1u16 << 9) {
        let edges = (0..9)
            .filter(|bit| mask & (1 << bit) != 0)
            .map(|bit| (bit / 3, bit % 3))
            .collect();
        let blocked = (0..3).filter(|node| mask & (1 << node) != 0).collect();
        result.push((edges, blocked));
    }
    let cycle = vec![(0, 1), (1, 2), (2, 0)];
    for mask in 0..8 {
        let blocked = (0..3).filter(|node| mask & (1 << node) != 0).collect();
        result.push((cycle.clone(), blocked));
    }
    result.push((vec![(0, 1), (0, 1), (1, 2)], vec![2]));
    result.push((vec![(2, 2), (2, 2), (0, 1)], vec![0, 0]));
    result
}

fn rust_rows(edges: &[Edge], blocked: &[u32]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32);
        relation block(u32);
        relation root(u32);
        relation path(u32, u32);
        relation witness(u32);
        relation safe(u32, u32);
        relation reach_count(u32, usize);
        relation selected(u32);
        lattice score(u32, CoordinateMax);

        path(x, y), witness(y) <-- edge(x, y);
        path(x, z) <-- path(x, y), edge(y, z);
        safe(x, y) <-- path(x, y), !block(y);
        reach_count(x, total) <-- root(x), agg total = count() in path(x, _);
        selected(x) <-- (witness(x) | root(x)), if *x % 2 == 0;
        score(to, CoordinateMax(*from, *to)) <-- edge(from, to);
        score(to, value.clone()) <-- score(from, ?value), edge(from, to);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        block: blocked.iter().map(|node| (*node,)).collect(),
        root: vec![(0,), (1,), (2,)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .path
            .iter()
            .map(|(from, to)| format!("path\t{from}\t{to}")),
    );
    rows.extend(
        program
            .witness
            .iter()
            .map(|(node,)| format!("witness\t{node}")),
    );
    rows.extend(
        program
            .safe
            .iter()
            .map(|(from, to)| format!("safe\t{from}\t{to}")),
    );
    rows.extend(
        program
            .reach_count
            .iter()
            .map(|(node, total)| format!("reach-count\t{node}\t{total}")),
    );
    rows.extend(
        program
            .selected
            .iter()
            .map(|(node,)| format!("selected\t{node}")),
    );
    rows.extend(
        program
            .score
            .iter()
            .map(|(node, CoordinateMax(first, second))| {
                format!("score\t{node}\t{first}\t{second}")
            }),
    );
    rows
}

fn render_snapshot(edges: &[Edge], blocked: &[u32]) -> String {
    let edge_rows = edges
        .iter()
        .map(|(from, to)| format!("({from} {to})"))
        .collect::<Vec<_>>()
        .join(" ");
    let blocked_nodes = blocked
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(" ");
    format!("(({edge_rows}) ({blocked_nodes}))")
}

fn scheme_request(cases: &[Case]) -> String {
    let rendered = cases
        .iter()
        .map(|(edges, blocked)| render_snapshot(edges, blocked))
        .collect::<Vec<_>>()
        .join(" ");
    format!("({rendered})\n")
}

fn session_additions(index: usize) -> (Edge, u32) {
    let from = (index % 3) as u32;
    ((from, (from + 1) % 3), (from + 1) % 3)
}

fn scheme_session_request(cases: &[Case]) -> String {
    let rendered = cases
        .iter()
        .enumerate()
        .map(|(index, (edges, blocked))| {
            let initial = render_snapshot(edges, blocked);
            let ((from, to), added_block) = session_additions(index);
            format!("({initial} ((({from} {to})) ({added_block})))")
        })
        .collect::<Vec<_>>()
        .join(" ");
    format!("(session ({rendered}))\n")
}

#[test]
fn complete_three_node_corpus_matches_rust_ascent() {
    let cases = cases();
    assert_eq!(cases.len(), 522);
    let output = scheme_output("integrated-corpus-rows", &scheme_request(&cases));
    let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    actual.sort_unstable();

    let mut expected = Vec::new();
    for (index, (edges, blocked)) in cases.iter().enumerate() {
        expected.extend(
            rust_rows(edges, blocked)
                .into_iter()
                .map(|row| format!("{index}\t{row}")),
        );
    }
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

#[test]
fn composed_nonpositive_sessions_match_fresh_fixed_points() {
    let cases = cases();
    let output = scheme_output("integrated-corpus-rows", &scheme_session_request(&cases));
    let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    actual.sort_unstable();

    let mut expected = Vec::new();
    for (index, (edges, blocked)) in cases.iter().enumerate() {
        expected.extend(
            rust_rows(edges, blocked)
                .into_iter()
                .map(|row| format!("{index}\t0\t{row}")),
        );
        let (added_edge, added_block) = session_additions(index);
        let mut combined_edges = edges.clone();
        combined_edges.push(added_edge);
        let mut combined_blocked = blocked.clone();
        combined_blocked.push(added_block);
        expected.extend(
            rust_rows(&combined_edges, &combined_blocked)
                .into_iter()
                .map(|row| format!("{index}\t1\t{row}")),
        );
        expected.extend(
            rust_rows(edges, blocked)
                .into_iter()
                .map(|row| format!("{index}\t2\t{row}")),
        );
    }
    expected.sort_unstable();
    if actual != expected {
        let first = actual
            .iter()
            .zip(&expected)
            .position(|(left, right)| left != right)
            .unwrap_or(actual.len().min(expected.len()));
        panic!(
            "composed session mismatch at {first}: Scheme {:?}, fresh Rust {:?} ({} vs {} rows)",
            actual.get(first),
            expected.get(first),
            actual.len(),
            expected.len()
        );
    }
}
