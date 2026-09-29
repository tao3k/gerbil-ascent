// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Two producers feed retained BYODS closure across mixed source updates.

use super::common::scheme_output;
use ascent::ascent;
use ascent_byods_rels::{trrel, trrel_uf};
use std::collections::BTreeSet;

type Edge = (u32, u32);

enum Update {
    Append(&'static str, Edge),
    Replace(&'static str, Vec<Edge>),
    InvalidReplace,
}

impl Update {
    fn scheme_form(&self) -> String {
        match self {
            Self::Append(name, (from, to)) => format!("(append {name} ({from} {to}))"),
            Self::Replace(name, rows) => format!("(replace {name} ({}))", render_edges(rows)),
            Self::InvalidReplace => "(invalid-replace left ((0 1 2)))".to_owned(),
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

fn render_edges(edges: &[Edge]) -> String {
    edges
        .iter()
        .map(|(from, to)| format!("({from} {to})"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn rows_from_rust(phase: usize, left: &[Edge], right: &[Edge]) -> Vec<String> {
    ascent! {
        relation left(u32, u32);
        relation right(u32, u32);
        #[ds(trrel)]
        relation strict(u32, u32);
        #[ds(trrel_uf)]
        relation reflexive(u32, u32);
        relation strict_output(u32, u32);
        relation reflexive_output(u32, u32);
        strict(x, y) <-- left(x, y);
        strict(x, y) <-- right(x, y);
        reflexive(x, y) <-- left(x, y);
        reflexive(x, y) <-- right(x, y);
        strict_output(x, y) <-- strict(x, y);
        reflexive_output(x, y) <-- reflexive(x, y);
    }
    let mut program = AscentProgram {
        left: left.to_vec(),
        right: right.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .strict_output
            .iter()
            .map(|(from, to)| format!("{phase}\tstrict-output\t{from}\t{to}")),
    );
    rows.extend(
        program
            .reflexive_output
            .iter()
            .map(|(from, to)| format!("{phase}\treflexive-output\t{from}\t{to}")),
    );
    rows.sort_unstable();
    rows
}

fn rows_from_model(phase: usize, left: &[Edge], right: &[Edge]) -> Vec<String> {
    let source: BTreeSet<_> = left.iter().chain(right).copied().collect();
    let nodes: BTreeSet<_> = source.iter().flat_map(|&(from, to)| [from, to]).collect();
    let mut rows = Vec::new();
    for &from in &nodes {
        let mut reached = BTreeSet::new();
        let mut pending = vec![from];
        while let Some(node) = pending.pop() {
            if reached.insert(node) {
                pending.extend(
                    source
                        .iter()
                        .filter_map(|&(left, right)| (left == node).then_some(right)),
                );
            }
        }
        for to in reached {
            if from != to || source.contains(&(from, from)) {
                rows.push(format!("{phase}\tstrict-output\t{from}\t{to}"));
            }
            rows.push(format!("{phase}\treflexive-output\t{from}\t{to}"));
        }
    }
    rows.sort_unstable();
    rows
}

#[test]
fn retained_two_producer_byods_matches_fresh_rust_and_closure_model() {
    let mut left = vec![(0, 1)];
    let mut right = vec![(1, 2)];
    let updates = [
        Update::Append("right", (2, 3)),
        Update::Append("left", (3, 0)),
        Update::Replace("right", vec![(0, 2)]),
        Update::Append("right", (2, 2)),
        Update::InvalidReplace,
        Update::Replace("left", vec![]),
        Update::Append("left", (2, 1)),
        Update::Append("left", (2, 1)),
        Update::Replace("right", vec![]),
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
    let output = scheme_output("byods-session-rows", &request);
    let mut scheme: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(scheme.pop().as_deref(), Some("END"));

    let mut expected = Vec::new();
    for phase in 0..=updates.len() {
        if let Some(update) = phase.checked_sub(1).and_then(|index| updates.get(index)) {
            update.apply(&mut left, &mut right);
        }
        let rust = rows_from_rust(phase, &left, &right);
        let model = rows_from_model(phase, &left, &right);
        assert_eq!(
            rust, model,
            "fresh Rust diverged from model in phase {phase}"
        );
        expected.extend(rust);
    }
    expected.sort_unstable();
    scheme.sort_unstable();
    assert_eq!(scheme, expected);
}
