// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Retained coordinatewise product lattice source and rule updates.

use super::common::{CoordinateMax, scheme_output};
use ascent::ascent;
use std::collections::BTreeMap;

type Triple = (u32, u32, u32);
type Snapshot = (Vec<Triple>, Vec<Triple>);
type Case = (Snapshot, Snapshot);

fn source_values() -> [Triple; 6] {
    [
        (0, 1, 4),
        (0, 4, 1),
        (0, 2, 3),
        (1, 3, 1),
        (1, 0, 5),
        (1, 5, 0),
    ]
}

fn cases(mixed: bool) -> Vec<Case> {
    let mut result = Vec::with_capacity(66);
    for mask in 0..(1u8 << 6) {
        let mut initial = (Vec::new(), Vec::new());
        let mut added = (Vec::new(), Vec::new());
        for (bit, value) in source_values().into_iter().enumerate() {
            if mask & (1 << bit) != 0 {
                match (mixed, bit % 2 == 0) {
                    (true, true) => initial.0.push(value),
                    (true, false) => added.0.push(value),
                    (false, true) => initial.1.push(value),
                    (false, false) => added.1.push(value),
                }
            }
        }
        if mixed {
            initial.1.extend([(0, 2, 2), (1, 1, 3)]);
            added.1.push((0, 3, 1));
        }
        result.push((initial, added));
    }
    for repeated in [[(0, 1, 4), (0, 4, 1)], [(1, 0, 5), (1, 5, 0)]] {
        let mut initial = (Vec::new(), Vec::new());
        let mut added = (Vec::new(), Vec::new());
        if mixed {
            initial.0.push(repeated[0]);
            added.0.extend([repeated[0], repeated[1]]);
            initial.1.push((0, 2, 2));
        } else {
            initial.1.push(repeated[0]);
            added.1.extend([repeated[0], repeated[1]]);
        }
        result.push((initial, added));
    }
    result
}

fn render_rows(rows: &[Triple]) -> String {
    rows.iter()
        .map(|(node, first, second)| format!("({node} {first} {second})"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn scheme_request(cases: &[Case]) -> String {
    let rendered = cases
        .iter()
        .map(
            |((scores, improvements), (added_scores, added_improvements))| {
                format!(
                    "((({}) ({})) (({}) ({})))",
                    render_rows(scores),
                    render_rows(improvements),
                    render_rows(added_scores),
                    render_rows(added_improvements)
                )
            },
        )
        .collect::<Vec<_>>()
        .join(" ");
    format!("({rendered})\n")
}

fn scheme_rows(cases: &[Case]) -> Vec<String> {
    let output = scheme_output("product-session-rows", &scheme_request(cases));
    let mut rows: Vec<_> = output.lines().map(str::to_owned).collect();
    assert_eq!(rows.pop().as_deref(), Some("END"));
    rows.sort_unstable();
    rows
}

fn canonical_rows(scores: &[Triple], improvements: &[Triple]) -> Vec<String> {
    let mut joined = BTreeMap::new();
    for &(node, first, second) in scores.iter().chain(improvements) {
        joined
            .entry(node)
            .and_modify(|old: &mut (u32, u32)| {
                old.0 = old.0.max(first);
                old.1 = old.1.max(second);
            })
            .or_insert((first, second));
    }
    let mut rows = Vec::new();
    for (node, (first, second)) in joined {
        rows.push(format!("score\t{node}\t{first}\t{second}"));
        rows.push(format!("copy\t{node}\t{first}\t{second}"));
    }
    rows.sort_unstable();
    rows
}

fn rust_phases(case: &Case) -> [Vec<String>; 2] {
    ascent! {
        lattice score(u32, CoordinateMax);
        relation improve(u32, u32, u32);
        lattice copy(u32, CoordinateMax);
        score(node, CoordinateMax(*first, *second)) <-- improve(node, first, second);
        copy(node, value.clone()) <-- score(node, ?value);
    }
    let rows = |program: &AscentProgram| {
        let mut result = Vec::new();
        result.extend(
            program
                .score
                .iter()
                .map(|(node, CoordinateMax(first, second))| {
                    format!("score\t{node}\t{first}\t{second}")
                }),
        );
        result.extend(
            program
                .copy
                .iter()
                .map(|(node, CoordinateMax(first, second))| {
                    format!("copy\t{node}\t{first}\t{second}")
                }),
        );
        result.sort_unstable();
        result
    };
    let ((scores, improvements), (added_scores, added_improvements)) = case;
    let mut retained = AscentProgram {
        score: scores
            .iter()
            .map(|&(node, first, second)| (node, CoordinateMax(first, second)))
            .collect(),
        improve: improvements.clone(),
        ..AscentProgram::default()
    };
    retained.run();
    let first = rows(&retained);
    retained.score.extend(
        added_scores
            .iter()
            .map(|&(node, first, second)| (node, CoordinateMax(first, second))),
    );
    retained.improve.extend(added_improvements);
    retained.run();
    [first, rows(&retained)]
}

#[test]
fn derived_product_sessions_match_pinned_rust_and_fixed_point() {
    let cases = cases(false);
    assert_eq!(cases.len(), 66);
    let actual = scheme_rows(&cases);
    let mut expected = Vec::new();
    for (index, case) in cases.iter().enumerate() {
        let rust = rust_phases(case);
        let ((_, initial), (_, added)) = case;
        let combined: Vec<_> = initial.iter().chain(added).copied().collect();
        assert_eq!(rust[0], canonical_rows(&[], initial));
        assert_eq!(rust[1], canonical_rows(&[], &combined));
        for (phase, rows) in rust.into_iter().enumerate() {
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
fn mixed_direct_product_sessions_match_coordinatewise_fixed_point() {
    let cases = cases(true);
    assert_eq!(cases.len(), 66);
    let actual = scheme_rows(&cases);
    let mut expected = Vec::new();
    for (index, ((scores, improvements), (added_scores, added_improvements))) in
        cases.iter().enumerate()
    {
        for (phase, (source, derived)) in [
            (scores.clone(), improvements.clone()),
            (
                scores.iter().chain(added_scores).copied().collect(),
                improvements
                    .iter()
                    .chain(added_improvements)
                    .copied()
                    .collect(),
            ),
        ]
        .into_iter()
        .enumerate()
        {
            expected.extend(
                canonical_rows(&source, &derived)
                    .into_iter()
                    .map(|row| format!("{index}\t{phase}\t{row}")),
            );
        }
    }
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

#[test]
fn pinned_rust_keeps_raw_incomparable_product_sources() {
    let case = (
        (vec![(0, 1, 4), (0, 4, 1)], vec![(0, 2, 2)]),
        (Vec::new(), Vec::new()),
    );
    let rust = rust_phases(&case);
    let canonical = canonical_rows(&case.0.0, &case.0.1);
    assert_ne!(rust[0], canonical);
    assert_eq!(
        rust[0],
        ["copy\t0\t4\t4", "score\t0\t1\t4", "score\t0\t4\t2"]
    );
}
