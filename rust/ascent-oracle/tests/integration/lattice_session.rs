// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Retained positive source updates through two recursive lattice families.

use super::common::scheme_output;
use ascent::{Dual, ascent, lattice::set::Set};

type Edge = (u32, u32, u32);
type Case = (Vec<Edge>, Vec<Edge>);
type Score = (u32, u32);
type ScoreCase = (Vec<Score>, Vec<Score>);

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

#[test]
fn rust_direct_lattice_source_update_matches_fresh_run() {
    ascent! {
        lattice score(u32, Dual<u32>);
        relation copy(u32, u32);
        copy(node, *value) <-- score(node, ?Dual(value));
    }
    let rows = |program: &AscentProgram| {
        let mut score = program
            .score
            .iter()
            .map(|(node, Dual(value))| (*node, *value))
            .collect::<Vec<_>>();
        score.sort_unstable();
        let mut copy = program.copy.clone();
        copy.sort_unstable();
        (score, copy)
    };
    let mut retained = AscentProgram {
        score: vec![(0, Dual(5))],
        ..AscentProgram::default()
    };
    retained.run();
    let first = rows(&retained);
    retained.score.push((0, Dual(3)));
    retained.run();
    let second = rows(&retained);
    let mut fresh = AscentProgram {
        score: vec![(0, Dual(5)), (0, Dual(3))],
        ..AscentProgram::default()
    };
    fresh.run();
    assert_eq!(
        second,
        rows(&fresh),
        "retained direct lattice source differs"
    );
    assert_eq!(first, (vec![(0, 5)], vec![(0, 5)]));
    assert_eq!(second, (vec![(0, 3), (0, 5)], vec![(0, 3), (0, 5)]));
}

fn direct_cases() -> Vec<ScoreCase> {
    let mut result = Vec::with_capacity(66);
    for mask in 0..(1u8 << 6) {
        let mut initial = Vec::new();
        let mut added = Vec::new();
        for bit in 0..6 {
            if mask & (1 << bit) != 0 {
                let score = (bit / 3, 1 + bit % 3);
                if bit % 2 == 0 {
                    initial.push(score);
                } else {
                    added.push(score);
                }
            }
        }
        result.push((initial, added));
    }
    result.push((vec![(0, 3)], vec![(0, 3), (0, 1)]));
    result.push((vec![(1, 2)], vec![(1, 2)]));
    result
}

fn direct_phases(initial: &[(u32, u32)], added: &[(u32, u32)]) -> [Vec<String>; 2] {
    ascent! {
        lattice score(u32, Dual<u32>);
        relation copy(u32, u32);
        copy(node, *value) <-- score(node, ?Dual(value));
    }
    let rows = |program: &AscentProgram| {
        let mut result = Vec::new();
        result.extend(
            program
                .score
                .iter()
                .map(|(node, Dual(value))| format!("score\t{node}\t{value}")),
        );
        result.extend(
            program
                .copy
                .iter()
                .map(|(node, value)| format!("copy\t{node}\t{value}")),
        );
        result.sort_unstable();
        result
    };
    let mut retained = AscentProgram {
        score: initial
            .iter()
            .map(|(node, value)| (*node, Dual(*value)))
            .collect(),
        ..AscentProgram::default()
    };
    retained.run();
    let first = rows(&retained);
    retained
        .score
        .extend(added.iter().map(|(node, value)| (*node, Dual(*value))));
    retained.run();
    let second = rows(&retained);
    let mut fresh = AscentProgram {
        score: initial
            .iter()
            .chain(added)
            .map(|(node, value)| (*node, Dual(*value)))
            .collect(),
        ..AscentProgram::default()
    };
    fresh.run();
    assert_eq!(second, rows(&fresh));
    [first, second]
}

#[test]
fn direct_lattice_source_corpus_matches_rust_ascent() {
    let cases = direct_cases();
    assert_eq!(cases.len(), 66);
    let render = |scores: &[(u32, u32)]| {
        scores
            .iter()
            .map(|(node, value)| format!("({node} {value})"))
            .collect::<Vec<_>>()
            .join(" ")
    };
    let rendered = cases
        .iter()
        .map(|(initial, added)| format!("(({}) ({}))", render(initial), render(added)))
        .collect::<Vec<_>>()
        .join(" ");
    let output = scheme_output(
        "lattice-session-corpus-rows",
        &format!("(direct ({rendered}))\n"),
    );
    let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    actual.sort_unstable();
    let mut expected = Vec::new();
    for (index, (initial, added)) in cases.iter().enumerate() {
        for (phase, rows) in direct_phases(initial, added).into_iter().enumerate() {
            expected.extend(
                rows.into_iter()
                    .map(|row| format!("{index}\t{phase}\t{row}")),
            );
        }
    }
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

#[test]
fn rust_raw_source_and_derived_lattice_join_probe() {
    ascent! {
        lattice score(u32, Dual<u32>);
        relation improve(u32, u32);
        relation copy(u32, u32);
        score(node, Dual(*value)) <-- improve(node, value);
        copy(node, *value) <-- score(node, ?Dual(value));
    }
    let mut program = AscentProgram {
        score: vec![(0, Dual(5)), (0, Dual(4))],
        improve: vec![(0, 2)],
        ..AscentProgram::default()
    };
    program.run();
    let mut score = program
        .score
        .iter()
        .map(|(node, Dual(value))| (*node, *value))
        .collect::<Vec<_>>();
    score.sort_unstable();
    program.copy.sort_unstable();
    assert_eq!(score, vec![(0, 2), (0, 5)]);
    assert_eq!(program.copy, vec![(0, 2), (0, 5)]);
}

#[test]
fn rust_mixed_lattice_repeated_run_retains_an_extra_public_row() {
    ascent! {
        lattice score(u32, Dual<u32>);
        relation improve(u32, u32);
        score(node, Dual(*value)) <-- improve(node, value);
    }
    let values = |program: &AscentProgram| {
        let mut rows = program
            .score
            .iter()
            .map(|(node, Dual(value))| (*node, *value))
            .collect::<Vec<_>>();
        rows.sort_unstable();
        rows
    };
    let mut retained = AscentProgram {
        improve: vec![(0, 2)],
        ..AscentProgram::default()
    };
    retained.run();
    retained.score.push((0, Dual(2)));
    retained.run();
    let mut fresh = AscentProgram {
        score: vec![(0, Dual(2))],
        improve: vec![(0, 2)],
        ..AscentProgram::default()
    };
    fresh.run();
    assert_eq!(values(&retained), vec![(0, 2), (0, 2)]);
    assert_eq!(values(&fresh), vec![(0, 2)]);
}
