// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Generated timeout API and retained fixed-point state in Ascent 0.8.0.

use super::common::scheme_output;
use ascent::ascent;
use std::{collections::BTreeSet, time::Duration};

#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
struct Node(u32);

#[test]
fn generated_timeout_partial_and_final_match_fixed_point() {
    ascent! {
        #![generate_run_timeout]
        relation edge(Node, Node);
        relation path(Node, Node);
        path(x, y) <-- edge(x, y);
        path(x, z) <-- path(x, y), edge(y, z);
    }
    let edges = (0..5)
        .map(|from| (Node(from), Node(from + 1)))
        .collect::<Vec<_>>();
    let mut partial = AscentProgram {
        edge: edges.clone(),
        ..AscentProgram::default()
    };
    assert!(!partial.run_timeout(Duration::ZERO));
    let rows = |path: &[(Node, Node)]| {
        path.iter()
            .map(|(from, to)| (from.0, to.0))
            .collect::<BTreeSet<_>>()
    };
    let observed = rows(&partial.path);
    assert_eq!(observed.len(), edges.len());
    let second = partial.run_timeout(Duration::ZERO);
    assert!(!second);
    let second_rows = rows(&partial.path);
    assert!(observed.is_subset(&second_rows));
    // Ascent 0.8.0 repeats the same visible rows at the second zero-budget
    // boundary. Scheme retains the committed delta and advances instead.
    assert_eq!(second_rows, observed);
    assert!(partial.run_timeout(Duration::MAX));

    let mut fresh = AscentProgram {
        edge: edges,
        ..AscentProgram::default()
    };
    fresh.run();
    let expected = rows(&fresh.path);
    assert!(observed.is_subset(&expected));
    assert_eq!(rows(&partial.path), expected);

    let scheme = scheme_output("timeout-rows", "((0 1) (1 2) (2 3) (3 4) (4 5))\n")
        .lines()
        .filter(|line| *line != "END")
        .map(str::to_owned)
        .collect::<Vec<_>>();
    let phase_rows = |phase: &str| {
        let prefix = format!("{phase}\t");
        scheme
            .iter()
            .filter_map(|line| line.strip_prefix(&prefix).map(str::to_owned))
            .collect::<BTreeSet<_>>()
    };
    for (phase, rows, finished) in [("first", &observed, false), ("full", &expected, true)] {
        let expected_rows = rows
            .iter()
            .map(|&(from, to)| format!("{from}\t{to}"))
            .collect::<BTreeSet<_>>();
        assert_eq!(phase_rows(phase), expected_rows);
        assert!(scheme.contains(&format!("finished\t{phase}\t{}", u8::from(finished))));
    }
    assert!(phase_rows("first").is_subset(&phase_rows("second")));
    assert!(phase_rows("second").len() > phase_rows("first").len());
}

#[test]
fn generated_timeout_resumes_recursion_before_negation() {
    ascent! {
        #![generate_run_timeout]
        relation edge(u32, u32);
        relation blocked(u32);
        relation path(u32, u32);
        relation allowed(u32, u32);
        path(x, y) <-- edge(x, y);
        path(x, z) <-- path(x, y), edge(y, z);
        allowed(x, y) <-- path(x, y), !blocked(y);
    }
    let mut program = AscentProgram {
        edge: vec![(0, 1), (1, 2), (2, 3)],
        blocked: vec![(2,)],
        ..AscentProgram::default()
    };
    assert!(!program.run_timeout(Duration::ZERO));
    let first_path = program.path.iter().copied().collect::<BTreeSet<_>>();
    assert_eq!(first_path, BTreeSet::from([(0, 1), (1, 2), (2, 3)]));
    assert!(program.allowed.is_empty());
    assert!(program.run_timeout(Duration::MAX));

    let final_path = program.path.iter().copied().collect::<BTreeSet<_>>();
    let final_allowed = program.allowed.iter().copied().collect::<BTreeSet<_>>();
    let expected_path = BTreeSet::from([(0, 1), (1, 2), (2, 3), (0, 2), (1, 3), (0, 3)]);
    let expected_allowed = BTreeSet::from([(0, 1), (0, 3), (1, 3), (2, 3)]);
    assert_eq!(final_path, expected_path);
    assert_eq!(final_allowed, expected_allowed);

    let output = scheme_output("timeout-strata-rows", "");
    let rows = output.lines().collect::<BTreeSet<_>>();
    assert!(rows.contains("finished\tfirst\t0"));
    assert!(rows.contains("finished\tsecond\t0"));
    assert!(rows.contains("finished\tfull\t1"));
    assert!(!rows.iter().any(|row| row.starts_with("first\tallowed\t")));
    assert!(rows.contains("END"));
    for (phase, relation, expected) in [
        ("first", "path", &first_path),
        ("full", "path", &final_path),
        ("full", "allowed", &final_allowed),
    ] {
        let actual = rows
            .iter()
            .filter_map(|row| {
                let prefix = format!("{phase}\t{relation}\t");
                row.strip_prefix(&prefix).map(str::to_owned)
            })
            .collect::<BTreeSet<_>>();
        let expected = expected
            .iter()
            .map(|(from, to)| format!("{from}\t{to}"))
            .collect::<BTreeSet<_>>();
        assert_eq!(actual, expected, "{phase} {relation}");
    }
    let second_path = rows
        .iter()
        .filter(|row| row.starts_with("second\tpath\t"))
        .count();
    assert!(second_path > first_path.len());
}
