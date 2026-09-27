// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Retained positive source updates through two recursive lattice families.

use super::common::scheme_output;
use ascent::{Dual, ascent, lattice::set::Set};

type Edge = (u32, u32, u32);
type Case = (Vec<Edge>, Vec<Edge>);

fn cases() -> Vec<Case> {
    let mut result = Vec::with_capacity(514);
    for mask in 0..(1u16 << 9) {
        let mut initial = Vec::new();
        let mut added = Vec::new();
        for bit in 0..9 {
            if mask & (1 << bit) != 0 {
                let edge = (bit / 3, bit % 3, 1 + bit % 3);
                if bit % 2 == 0 {
                    initial.push(edge);
                } else {
                    added.push(edge);
                }
            }
        }
        result.push((initial, added));
    }
    result.push((vec![(0, 1, 3)], vec![(0, 1, 3), (1, 2, 1)]));
    result.push((vec![(1, 1, 2)], vec![(1, 1, 2)]));
    result
}

fn rust_phases(initial: &[Edge], added: &[Edge]) -> [Vec<String>; 2] {
    ascent! {
        relation edge(u32, u32, u32);
        lattice shortest(u32, u32, Dual<u32>);
        lattice reach_tag(u32, Set<u32>);
        shortest(from, to, Dual(*weight)) <-- edge(from, to, weight);
        shortest(from, to, Dual(first + weight)) <--
            shortest(from, via, ?Dual(first)), edge(via, to, weight);
        reach_tag(from, Set::singleton(*from)) <-- edge(from, _, _);
        reach_tag(to, tags.clone()) <--
            reach_tag(from, ?tags), edge(from, to, _);
    }
    let rows = |program: &AscentProgram| {
        let mut result = Vec::new();
        result.extend(
            program
                .shortest
                .iter()
                .map(|(from, to, Dual(distance))| format!("shortest\t{from}\t{to}\t{distance}")),
        );
        result.extend(program.reach_tag.iter().flat_map(|(node, tags)| {
            tags.iter()
                .map(move |tag| format!("reach-tag\t{node}\t{tag}"))
        }));
        result.sort_unstable();
        result
    };
    let mut program = AscentProgram {
        edge: initial.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let first = rows(&program);
    program.edge.extend_from_slice(added);
    program.run();
    let second = rows(&program);
    let mut fresh = AscentProgram {
        edge: program.edge.clone(),
        ..AscentProgram::default()
    };
    fresh.run();
    assert_eq!(
        second,
        rows(&fresh),
        "retained Rust lattice differs from fresh"
    );
    [first, second]
}

fn scheme_request(cases: &[Case]) -> String {
    let render = |edges: &[Edge]| {
        edges
            .iter()
            .map(|(from, to, weight)| format!("({from} {to} {weight})"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    let rendered = cases
        .iter()
        .map(|(initial, added)| format!("(({}) ({}))", render(initial), render(added)))
        .collect::<Vec<_>>()
        .join(" ");
    format!("({rendered})\n")
}

#[test]
fn every_three_node_lattice_session_matches_rust_ascent() {
    let cases = cases();
    assert_eq!(cases.len(), 514);
    let output = scheme_output("lattice-session-corpus-rows", &scheme_request(&cases));
    let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    actual.sort_unstable();

    let mut expected = Vec::new();
    for (index, (initial, added)) in cases.iter().enumerate() {
        for (phase, rows) in rust_phases(initial, added).into_iter().enumerate() {
            expected.extend(
                rows.into_iter()
                    .map(|row| format!("{index}\t{phase}\t{row}")),
            );
        }
    }
    expected.sort_unstable();
    assert_eq!(actual, expected);
}
