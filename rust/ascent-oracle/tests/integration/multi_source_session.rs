// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Retained Scheme updates against fresh Rust and an independent finite model.

use super::common::scheme_output;
use ascent::aggregators::count;
use ascent::ascent;
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
            Self::InvalidReplace => "(invalid-replace blocked ((0 1 2)))".to_owned(),
        }
    }

    fn apply(&self, edges: &mut Vec<Edge>, blocked: &mut Vec<Edge>) {
        match self {
            Self::Append("edge", edge) => edges.push(*edge),
            Self::Append("blocked", edge) => blocked.push(*edge),
            Self::Replace("edge", rows) => *edges = rows.clone(),
            Self::Replace("blocked", rows) => *blocked = rows.clone(),
            Self::InvalidReplace => {}
            _ => unreachable!("the corpus declares only edge and blocked sources"),
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

fn rows_from_rust(phase: usize, edges: &[Edge], blocked: &[Edge]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32);
        relation blocked(u32, u32);
        relation reach(u32, u32);
        relation allowed(u32, u32);
        relation total(usize);
        reach(x, y) <-- edge(x, y);
        reach(x, z) <-- reach(x, y), edge(y, z);
        allowed(x, y) <-- reach(x, y), !blocked(x, y);
        total(n) <-- agg n = count() in allowed(_, _);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        blocked: blocked.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .reach
            .iter()
            .map(|(from, to)| format!("{phase}\treach\t{from}\t{to}")),
    );
    rows.extend(
        program
            .allowed
            .iter()
            .map(|(from, to)| format!("{phase}\tallowed\t{from}\t{to}")),
    );
    rows.extend(
        program
            .total
            .iter()
            .map(|(count,)| format!("{phase}\ttotal\t{count}")),
    );
    rows.sort_unstable();
    rows
}

fn rows_from_model(phase: usize, edges: &[Edge], blocked: &[Edge]) -> Vec<String> {
    let source: BTreeSet<_> = edges.iter().copied().collect();
    let excluded: BTreeSet<_> = blocked.iter().copied().collect();
    let mut reach = source.clone();
    loop {
        let previous = reach.len();
        let known: Vec<_> = reach.iter().copied().collect();
        for (from, middle) in known {
            for &(next, to) in &source {
                if middle == next {
                    reach.insert((from, to));
                }
            }
        }
        if reach.len() == previous {
            break;
        }
    }
    let allowed: Vec<_> = reach.difference(&excluded).copied().collect();
    let mut rows = Vec::new();
    rows.extend(
        reach
            .iter()
            .map(|(from, to)| format!("{phase}\treach\t{from}\t{to}")),
    );
    rows.extend(
        allowed
            .iter()
            .map(|(from, to)| format!("{phase}\tallowed\t{from}\t{to}")),
    );
    rows.push(format!("{phase}\ttotal\t{}", allowed.len()));
    rows.sort_unstable();
    rows
}

#[test]
fn retained_multi_source_updates_match_fresh_rust_and_finite_model() {
    let mut edges = vec![(0, 1), (1, 2)];
    let mut blocked = Vec::new();
    let updates = [
        Update::Append("blocked", (0, 2)),
        Update::Append("edge", (2, 0)),
        Update::Replace("edge", vec![(0, 1), (1, 0)]),
        Update::Replace("blocked", vec![(0, 1)]),
        Update::InvalidReplace,
        Update::Append("blocked", (1, 0)),
        Update::Replace("blocked", vec![]),
        Update::Append("edge", (1, 2)),
        Update::Append("edge", (1, 2)),
    ];
    let request = format!(
        "((({}) ({})) {})\n",
        render_edges(&edges),
        render_edges(&blocked),
        updates
            .iter()
            .map(Update::scheme_form)
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("multi-source-session-rows", &request);
    let mut scheme: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(scheme.pop().as_deref(), Some("END"));

    let mut expected = Vec::new();
    for phase in 0..=updates.len() {
        if let Some(update) = phase.checked_sub(1).and_then(|index| updates.get(index)) {
            update.apply(&mut edges, &mut blocked);
        }
        let rust = rows_from_rust(phase, &edges, &blocked);
        let model = rows_from_model(phase, &edges, &blocked);
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
