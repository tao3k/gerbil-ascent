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
