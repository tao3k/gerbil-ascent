// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Binary closure, guards and source support.

use super::common::scheme_output;
use ascent::{Dual, ascent};
use std::{
    cmp::Reverse,
    collections::{BTreeSet, BinaryHeap},
};

fn pair_request(edges: &[(u32, u32)], generic: bool) -> String {
    let mut request = String::from(if generic { "(generic 8" } else { "(8" });
    for &(from, to) in edges {
        assert!(from < 8 && to < 8);
        request.push_str(&format!(" {from} {to}"));
    }
    request.push_str(")\n");
    request
}

fn parse_pair(line: &str) -> (u32, u32) {
    let (from, to) = line.split_once('\t').expect("Scheme pair has two columns");
    (
        from.parse().expect("numeric from"),
        to.parse().expect("numeric to"),
    )
}

pub(super) fn scheme_pairs(edges: &[(u32, u32)], generic: bool) -> Vec<(u32, u32)> {
    scheme_output("ascent-pairs", &pair_request(edges, generic))
        .lines()
        .map(parse_pair)
        .collect()
}

fn ascent_pairs(edges: &[(u32, u32)]) -> Vec<(u32, u32)> {
    ascent! {
        relation edge(u32, u32);
        relation reach(u32, u32);
        reach(from, to) <-- edge(from, to);
        reach(from, to) <-- reach(from, via), edge(via, to);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    program.reach.sort_unstable();
    program.reach
}

#[test]
fn fast_and_composable_closure_match_ascent() {
    let snapshots: &[&[(u32, u32)]] = &[
        &[],
        &[(1, 1)],
        &[(1, 1), (1, 1), (1, 2)],
        &[(0, 1), (1, 0), (2, 3), (3, 2), (4, 4)],
        &[(1, 2), (2, 3), (1, 4), (4, 3)],
        &[(1, 2), (1, 4), (4, 3)],
        &[(1, 2), (1, 4)],
        &[(1, 2), (2, 3), (3, 4), (4, 2), (1, 3)],
        &[(1, 2), (2, 3), (3, 4), (1, 3)],
    ];
    for (index, edges) in snapshots.iter().enumerate() {
        let expected = ascent_pairs(edges);
        assert_eq!(
            scheme_pairs(edges, false),
            expected,
            "fast snapshot {index}"
        );
        assert_eq!(
            scheme_pairs(edges, true),
            expected,
            "generic snapshot {index}"
        );
    }
}

#[derive(Debug, Eq, PartialEq)]
struct GuardedRows {
    selected: BTreeSet<(u32, u32)>,
    copied: BTreeSet<(u32, u32)>,
    twohop: BTreeSet<(u32, u32)>,
}

fn ascent_guarded(edges: &[(u32, u32)]) -> GuardedRows {
    ascent! {
        relation edge(u32, u32);
        relation selected(u32, u32);
        relation copied(u32, u32);
        relation twohop(u32, u32);
        selected(from, to) <-- edge(from, to), if from % 2 == 0;
        copied(from, to) <-- selected(from, to);
        twohop(from, to) <-- selected(from, via), edge(via, to);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    GuardedRows {
        selected: program.selected.into_iter().collect(),
        copied: program.copied.into_iter().collect(),
        twohop: program.twohop.into_iter().collect(),
    }
}

fn scheme_guarded(edges: &[(u32, u32)]) -> GuardedRows {
    let mut rows = GuardedRows {
        selected: BTreeSet::new(),
        copied: BTreeSet::new(),
        twohop: BTreeSet::new(),
    };
    for line in scheme_output("ascent-guarded", &pair_request(edges, false)).lines() {
        let mut fields = line.split('\t');
        let relation = fields.next().expect("relation name");
        let from = fields
            .next()
            .expect("from node")
            .parse()
            .expect("numeric from");
        let to = fields.next().expect("to node").parse().expect("numeric to");
        assert!(fields.next().is_none(), "unexpected Scheme output field");
        let target = match relation {
            "selected" => &mut rows.selected,
            "copied" => &mut rows.copied,
            "twohop" => &mut rows.twohop,
            other => panic!("unknown Scheme relation: {other}"),
        };
        assert!(target.insert((from, to)), "duplicate Scheme output row");
    }
    rows
}

#[test]
fn guarded_filter_copy_and_join_match_ascent() {
    let snapshots: &[&[(u32, u32)]] = &[
        &[(1, 2), (2, 3), (2, 4), (4, 5), (3, 5)],
        &[(1, 2), (2, 3), (2, 4), (3, 5)],
        &[(1, 2), (2, 3), (2, 4)],
        &[(1, 2), (3, 4)],
        &[(2, 2), (2, 3), (3, 4)],
    ];
    for (index, edges) in snapshots.iter().enumerate() {
        assert_eq!(
            scheme_guarded(edges),
            ascent_guarded(edges),
            "guarded snapshot {index}"
        );
    }
}

#[derive(Debug, Eq, PartialEq, Ord, PartialOrd)]
struct SupportRow {
    from: u32,
    to: u32,
    distance: usize,
    rule: String,
    support: Vec<u32>,
}

fn shortest_support(edges: &[(u32, u32, u32)], origin: u32, target: u32) -> Vec<u32> {
    let node_count = edges
        .iter()
        .flat_map(|&(from, to, _)| [from, to])
        .collect::<BTreeSet<_>>()
        .len();
    let mut frontier = BinaryHeap::from([Reverse((0_usize, Vec::<u32>::new(), origin))]);
    while let Some(Reverse((distance, support, node))) = frontier.pop() {
        if distance > 0 && node == target {
            return support;
        }
        if distance == node_count {
            continue;
        }
        for &(from, to, label) in edges {
            if from == node {
                let mut next = support.clone();
                next.push(label);
                frontier.push(Reverse((distance + 1, next, to)));
            }
        }
    }
    panic!("Ascent pair has no source support");
}

fn ascent_support(edges: &[(u32, u32, u32)]) -> Vec<SupportRow> {
    ascent! {
        relation edge(u32, u32, u32);
        lattice path(u32, u32, Dual<usize>);
        path(from, to, Dual(1_usize)) <-- edge(from, to, _label);
        path(from, to, Dual(distance + 1)) <--
            path(from, via, ?Dual(distance)), edge(via, to, _label);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .path
        .into_iter()
        .map(|(from, to, Dual(distance))| SupportRow {
            from,
            to,
            distance,
            rule: if distance == 1 { "base" } else { "transitive" }.into(),
            support: shortest_support(edges, from, to),
        })
        .collect();
    rows.sort();
    rows
}

fn scheme_support(edges: &[(u32, u32, u32)]) -> Vec<SupportRow> {
    let mut request = String::from("(8");
    for &(from, to, label) in edges {
        request.push_str(&format!(" {from} {to} {label}"));
    }
    request.push_str(")\n");
    let mut rows: Vec<_> = scheme_output("ascent-candidates", &request)
        .lines()
        .map(|line| {
            let mut fields = line.split('\t');
            SupportRow {
                from: fields.next().expect("from").parse().expect("numeric from"),
                to: fields.next().expect("to").parse().expect("numeric to"),
                distance: fields
                    .next()
                    .expect("distance")
                    .parse()
                    .expect("numeric distance"),
                rule: fields.next().expect("rule").to_owned(),
                support: fields
                    .map(|label| label.parse().expect("numeric source label"))
                    .collect(),
            }
        })
        .collect();
    rows.sort();
    rows
}

#[test]
fn shortest_support_matches_ascent_and_canonical_source_order() {
    let snapshots: &[&[(u32, u32, u32)]] = &[
        &[(1, 2, 100), (2, 3, 101), (1, 4, 99), (4, 3, 103)],
        &[(1, 2, 100), (1, 4, 99), (4, 3, 103)],
        &[(1, 2, 100), (1, 4, 99)],
        &[
            (1, 2, 100),
            (2, 3, 101),
            (3, 4, 102),
            (4, 2, 103),
            (1, 3, 104),
        ],
        &[(1, 2, 100), (2, 3, 101), (3, 4, 102), (1, 3, 104)],
    ];
    for (index, edges) in snapshots.iter().enumerate() {
        let expected = ascent_support(edges);
        assert!(expected.iter().all(|row| row.distance == row.support.len()));
        assert_eq!(scheme_support(edges), expected, "support snapshot {index}");
    }
}
