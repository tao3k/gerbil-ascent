// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Retained grouped equivalence under source withdrawal and two producers.

use super::common::scheme_output;
use ascent::ascent;
use ascent_byods_rels::eqrel;
use std::collections::{BTreeMap, BTreeSet};

type Edge = (&'static str, u32, u32);

enum Update {
    Append(&'static str, Edge),
    Replace(&'static str, Vec<Edge>),
    InvalidReplace,
}

impl Update {
    fn scheme_form(&self) -> String {
        match self {
            Self::Append(name, edge) => format!("(append {name} {})", render_edge(edge)),
            Self::Replace(name, rows) => format!("(replace {name} ({}))", render_edges(rows)),
            Self::InvalidReplace => "(invalid-replace left ((\"alpha\" 1 2 3)))".to_owned(),
        }
    }

    fn apply(&self, left: &mut Vec<Edge>, right: &mut Vec<Edge>) {
        match self {
            Self::Append("left", edge) => left.push(*edge),
            Self::Append("right", edge) => right.push(*edge),
            Self::Replace("left", rows) => *left = rows.clone(),
            Self::Replace("right", rows) => *right = rows.clone(),
            Self::InvalidReplace => {}
            _ => unreachable!("the corpus declares only left and right sources"),
        }
    }
}

fn render_edge((group, from, to): &Edge) -> String {
    format!("(\"{group}\" {from} {to})")
}

fn render_edges(edges: &[Edge]) -> String {
    edges.iter().map(render_edge).collect::<Vec<_>>().join(" ")
}

fn rows_from_fresh_rust(phase: usize, left: &[Edge], right: &[Edge]) -> Vec<String> {
    ascent! {
        relation seed(String, u32, u32);
        #[ds(eqrel)]
        relation equivalent(String, u32, u32);
        relation output(String, u32, u32);
        equivalent(g, x, y) <-- seed(g, x, y);
        output(g, x, y) <-- equivalent(g, x, y);
    }
    let mut program = AscentProgram {
        seed: left
            .iter()
            .chain(right)
            .map(|&(group, from, to)| (group.to_owned(), from, to))
            .collect(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = program
        .output
        .iter()
        .map(|(group, from, to)| format!("{phase}\tequivalent-output\t{group}\t{from}\t{to}"))
        .collect::<Vec<_>>();
    rows.sort_unstable();
    rows
}

fn rows_from_model(phase: usize, left: &[Edge], right: &[Edge]) -> Vec<String> {
    let mut groups = BTreeMap::<&str, BTreeSet<(u32, u32)>>::new();
    for &(group, from, to) in left.iter().chain(right) {
        groups.entry(group).or_default().insert((from, to));
    }
    let mut rows = Vec::new();
    for (group, edges) in groups {
        let nodes: BTreeSet<_> = edges.iter().flat_map(|&(from, to)| [from, to]).collect();
        for &from in &nodes {
            let mut connected = BTreeSet::new();
            let mut pending = vec![from];
            while let Some(node) = pending.pop() {
                if connected.insert(node) {
                    pending.extend(edges.iter().filter_map(|&(left, right)| {
                        if left == node {
                            Some(right)
                        } else if right == node {
                            Some(left)
                        } else {
                            None
                        }
                    }));
                }
            }
            rows.extend(
                connected
                    .into_iter()
                    .map(|to| format!("{phase}\tequivalent-output\t{group}\t{from}\t{to}")),
            );
        }
    }
    rows.sort_unstable();
    rows
}

#[test]
fn grouped_eqrel_retained_updates_match_single_producer_rust_and_model() {
    let mut left = vec![("alpha", 1, 2), ("beta", 5, 6)];
    let mut right = vec![("alpha", 2, 3), ("beta", 7, 8)];
    let updates = [
        Update::Append("right", ("beta", 6, 7)),
        Update::Append("left", ("alpha", 3, 4)),
        Update::Replace("right", vec![("alpha", 2, 4), ("beta", 7, 8)]),
        Update::InvalidReplace,
        Update::Replace("left", vec![]),
        Update::Append("left", ("beta", 8, 9)),
        Update::Append("left", ("beta", 8, 9)),
        Update::Replace("right", vec![]),
        Update::Append("left", ("alpha", 4, 4)),
    ];
    let request = format!(
        "((({}) ({})) {})\n",
        render_edges(&left),
        render_edges(&right),
        updates
            .iter()
            .map(Update::scheme_form)
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("grouped-eqrel-session-rows", &request);
    let mut scheme: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(scheme.pop().as_deref(), Some("END"));

    let mut expected = Vec::new();
    for phase in 0..=updates.len() {
        if let Some(update) = phase.checked_sub(1).and_then(|index| updates.get(index)) {
            update.apply(&mut left, &mut right);
        }
        let rust = rows_from_fresh_rust(phase, &left, &right);
        let model = rows_from_model(phase, &left, &right);
        assert_eq!(rust, model, "single-producer Rust differs in phase {phase}");
        expected.extend(model);
    }
    expected.sort_unstable();
    scheme.sort_unstable();
    assert_eq!(scheme, expected);
}
