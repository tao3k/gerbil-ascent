// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! BYODS equivalence feeds a recursive lattice, negation, and aggregation.

use super::common::scheme_output;
use ascent::{ascent, lattice::Dual};
use ascent_byods_rels::eqrel;
use std::collections::BTreeSet;

type Edge = (u32, u32);

fn edges_for(mask: u32) -> Vec<Edge> {
    (0..3)
        .flat_map(|from| (0..3).map(move |to| (from, to)))
        .enumerate()
        .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(edge))
        .collect()
}

#[allow(clippy::clone_on_copy, reason = "Ascent 0.8.0 macro expansion")]
fn rust_rows(edges: &[Edge], seeds: &[Edge], roots: &[u32]) -> BTreeSet<String> {
    ascent! {
        relation edge(u32, u32);
        relation seed(u32, u32);
        relation root(u32);
        #[ds(eqrel)]
        relation equivalent(u32, u32);
        relation equivalent_output(u32, u32);
        lattice score(u32, Dual<u32>);
        relation cheap(u32);
        relation not_cheap(u32);
        relation not_count(usize);

        equivalent(from, to) <-- edge(from, to);
        equivalent_output(from, to) <-- equivalent(from, to);
        score(node, Dual(*value)) <-- seed(node, value);
        score(to, value.clone()) <-- score(from, ?value), equivalent(from, to);
        cheap(node) <-- score(node, ?Dual(value)), if *value <= 2;
        not_cheap(node) <-- root(node), !cheap(node);
        not_count(total) <-- agg total = ascent::aggregators::count() in not_cheap(_);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        seed: seeds.to_vec(),
        root: roots.iter().map(|&node| (node,)).collect(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = BTreeSet::new();
    rows.extend(
        program
            .equivalent_output
            .iter()
            .map(|(from, to)| format!("equivalent-output\t{from}\t{to}")),
    );
    rows.extend(
        program
            .score
            .iter()
            .map(|(node, Dual(value))| format!("score\t{node}\t{value}")),
    );
    rows.extend(program.cheap.iter().map(|(node,)| format!("cheap\t{node}")));
    rows.extend(
        program
            .not_cheap
            .iter()
            .map(|(node,)| format!("not-cheap\t{node}")),
    );
    rows.extend(
        program
            .not_count
            .iter()
            .map(|(total,)| format!("not-count\t{total}")),
    );
    rows
}

fn model_rows(edges: &[Edge], seeds: &[Edge], roots: &[u32]) -> BTreeSet<String> {
    let source = edges.iter().copied().collect::<BTreeSet<_>>();
    let active = source
        .iter()
        .flat_map(|&(from, to)| [from, to])
        .collect::<BTreeSet<_>>();
    let mut rows = BTreeSet::new();
    let mut not_count = 0;
    for &node in roots {
        let mut connected = BTreeSet::new();
        let mut pending = vec![node];
        while let Some(current) = pending.pop() {
            if connected.insert(current) {
                pending.extend(source.iter().filter_map(|&(from, to)| {
                    if from == current {
                        Some(to)
                    } else if to == current {
                        Some(from)
                    } else {
                        None
                    }
                }));
            }
        }
        if active.contains(&node) {
            rows.extend(
                connected
                    .iter()
                    .map(|to| format!("equivalent-output\t{node}\t{to}")),
            );
        }
        let minimum = seeds
            .iter()
            .filter_map(|&(index, value)| connected.contains(&index).then_some(value))
            .min()
            .expect("every root component has a seed");
        rows.insert(format!("score\t{node}\t{minimum}"));
        if minimum <= 2 {
            rows.insert(format!("cheap\t{node}"));
        } else {
            rows.insert(format!("not-cheap\t{node}"));
            not_count += 1;
        }
    }
    rows.insert(format!("not-count\t{not_count}"));
    rows
}

#[test]
fn eqrel_lattice_negative_aggregate_matches_all_three_node_graphs() {
    let seeds = [(0, 2), (1, 3), (2, 5)];
    let roots = [0, 1, 2];
    let request = format!(
        "({})\n",
        (0..512)
            .map(|mask| {
                let edges = edges_for(mask)
                    .into_iter()
                    .map(|(from, to)| format!("({from} {to})"))
                    .collect::<Vec<_>>()
                    .join(" ");
                format!("({mask} ({edges}))")
            })
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("byods-lattice-rows", &request);
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    let scheme = scheme.into_iter().collect::<BTreeSet<_>>();
    let mut expected = BTreeSet::new();
    for mask in 0..512 {
        let edges = edges_for(mask);
        let rust = rust_rows(&edges, &seeds, &roots);
        let model = model_rows(&edges, &seeds, &roots);
        assert_eq!(rust, model, "Rust mask={mask}");
        expected.extend(model.into_iter().map(|row| format!("{mask}\t{row}")));
    }
    assert_eq!(scheme, expected);
}

#[test]
fn retained_eqrel_lattice_updates_timeout_and_failure_recovery() {
    let request = "((() ((0 2) (1 3) (2 5)) ((0) (1) (2))) \
        (replace edge ((0 1))) \
        (invalid-replace seed ((0))) \
        (append edge (1 2)) \
        (append edge (1 2)) \
        (replace seed ((0 4) (1 3) (2 5))) \
        (replace edge ((0 2))) \
        (replace seed ((0 2) (1 3) (2 5))))\n";
    let output = scheme_output("byods-lattice-session-rows", request);
    let mut actual = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(actual.pop().as_deref(), Some("END"));
    let mut timeout_rows = Vec::new();
    let mut scheme_rows = BTreeSet::new();
    for row in actual {
        if row.contains("\ttimeout\t") {
            timeout_rows.push(row);
        } else {
            scheme_rows.insert(row);
        }
    }
    assert_eq!(timeout_rows.len(), 8);
    assert_eq!(timeout_rows[0], "0\ttimeout\t0\t0\t1");
    assert_eq!(timeout_rows[1], "1\ttimeout\t0\t0\t1");
    assert_eq!(timeout_rows[2], "2\ttimeout\t1\t1\t1");
    assert!(timeout_rows.iter().all(|row| row.ends_with("\t1")));

    let states: [(Vec<Edge>, Vec<Edge>); 8] = [
        (vec![], vec![(0, 2), (1, 3), (2, 5)]),
        (vec![(0, 1)], vec![(0, 2), (1, 3), (2, 5)]),
        (vec![(0, 1)], vec![(0, 2), (1, 3), (2, 5)]),
        (vec![(0, 1), (1, 2)], vec![(0, 2), (1, 3), (2, 5)]),
        (vec![(0, 1), (1, 2)], vec![(0, 2), (1, 3), (2, 5)]),
        (vec![(0, 1), (1, 2)], vec![(0, 4), (1, 3), (2, 5)]),
        (vec![(0, 2)], vec![(0, 4), (1, 3), (2, 5)]),
        (vec![(0, 2)], vec![(0, 2), (1, 3), (2, 5)]),
    ];
    let mut expected = BTreeSet::new();
    for (phase, (edges, seeds)) in states.iter().enumerate() {
        let rust = rust_rows(edges, seeds, &[0, 1, 2]);
        let model = model_rows(edges, seeds, &[0, 1, 2]);
        assert_eq!(rust, model, "Rust phase={phase}");
        expected.extend(model.into_iter().map(|row| format!("{phase}\t{row}")));
    }
    assert_eq!(scheme_rows, expected);
}

fn compare_pair_scale(size: u32) {
    let edges = (0..size)
        .map(|pair| (pair * 2, pair * 2 + 1))
        .collect::<Vec<_>>();
    let seeds = (0..size)
        .flat_map(|pair| {
            [
                (pair * 2, 5),
                (pair * 2 + 1, if pair % 2 == 0 { 2 } else { 3 }),
            ]
        })
        .collect::<Vec<_>>();
    let roots = (0..size * 2).collect::<Vec<_>>();
    let mut model = BTreeSet::new();
    for pair in 0..size {
        let left = pair * 2;
        let right = left + 1;
        let minimum = if pair % 2 == 0 { 2 } else { 3 };
        for (from, to) in [(left, left), (left, right), (right, left), (right, right)] {
            model.insert(format!("equivalent-output\t{from}\t{to}"));
        }
        for node in [left, right] {
            model.insert(format!("score\t{node}\t{minimum}"));
            model.insert(format!(
                "{}\t{node}",
                if pair % 2 == 0 { "cheap" } else { "not-cheap" }
            ));
        }
    }
    model.insert(format!("not-count\t{size}"));
    assert_eq!(model.len(), (size * 8 + 1) as usize);
    let rust = rust_rows(&edges, &seeds, &roots);
    assert_eq!(rust, model, "Rust pair count={size}");
    let output = scheme_output("byods-lattice-scale-rows", &format!("{size}\n"));
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    assert_eq!(scheme.into_iter().collect::<BTreeSet<_>>(), model);
}

#[test]
fn eqrel_lattice_negative_aggregate_matches_1000_disjoint_pairs() {
    compare_pair_scale(1000);
}

#[test]
fn eqrel_lattice_negative_aggregate_matches_10000_disjoint_pairs() {
    compare_pair_scale(10000);
}
