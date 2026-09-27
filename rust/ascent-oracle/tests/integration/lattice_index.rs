// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Recursive lattice joins and composite indexes.

use super::common::scheme_output;
use ascent::{Dual, ascent, lattice::set::Set};

fn ascent_lattice_rows(edges: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32, u32);
        lattice shortest(u32, u32, Dual<u32>);
        shortest(x, y, Dual(*weight)) <-- edge(x, y, weight);
        shortest(x, z, Dual(first + second)) <--
            shortest(x, y, ?Dual(first)), edge(y, z, second);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .shortest
        .iter()
        .map(|(from, to, Dual(distance))| format!("{from}\t{to}\t{distance}"))
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn recursive_lattice_join_matches_ascent() {
    let snapshots: &[&[(u32, u32, u32)]] = &[
        &[],
        &[(1, 2, 3), (1, 3, 1), (3, 2, 1), (2, 4, 1), (3, 4, 5)],
        &[(1, 2, 5), (1, 2, 2), (2, 3, 1)],
        &[(1, 2, 3), (2, 1, 1)],
    ];
    for edges in snapshots {
        let request = format!(
            "({})\n",
            edges
                .iter()
                .map(|(from, to, weight)| format!("({from} {to} {weight})"))
                .collect::<Vec<_>>()
                .join(" ")
        );
        let output = scheme_output("lattice-rows", &request);
        let mut rows: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(rows.pop().as_deref(), Some("END"));
        rows.sort_unstable();
        assert_eq!(rows, ascent_lattice_rows(edges), "edges: {edges:?}");
    }
}

fn ascent_set_lattice_rows(seeds: &[(u32, u32)], edges: &[(u32, u32)]) -> Vec<String> {
    ascent! {
        relation seed(u32, u32);
        relation edge(u32, u32);
        lattice reach_tag(u32, Set<u32>);
        reach_tag(node, Set::singleton(*tag)) <-- seed(node, tag);
        reach_tag(to, tags.clone()) <-- reach_tag(from, ?tags), edge(from, to);
    }
    let mut program = AscentProgram {
        seed: seeds.to_vec(),
        edge: edges.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .reach_tag
        .iter()
        .flat_map(|(node, tags)| tags.iter().map(move |tag| format!("{node}\t{tag}")))
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn set_lattice_union_and_recursive_propagation_match_ascent() {
    type Pairs = [(u32, u32)];
    let snapshots: &[(&Pairs, &Pairs)] = &[
        (&[], &[]),
        (&[(1, 7), (1, 9), (1, 7)], &[]),
        (&[(1, 7), (2, 9)], &[(1, 3), (2, 3), (3, 4)]),
        (&[(1, 7), (2, 9)], &[(1, 2), (2, 1), (2, 3)]),
    ];
    for (seeds, edges) in snapshots {
        let rows = |pairs: &[(u32, u32)]| {
            pairs
                .iter()
                .map(|(left, right)| format!("({left} {right})"))
                .collect::<Vec<_>>()
                .join(" ")
        };
        let request = format!("({})\n({})\n", rows(seeds), rows(edges));
        let output = scheme_output("lattice-set-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_set_lattice_rows(seeds, edges));
    }
}

#[test]
fn indexed_two_hop_join_matches_ascent() {
    ascent! {
        relation edge(u32, u32);
        relation two_hop(u32, u32);
        two_hop(from, to) <-- edge(from, via), edge(via, to);
    }
    let edges: Vec<_> = (0..50).map(|from| (from, from + 1)).collect();
    let mut program = AscentProgram {
        edge: edges,
        ..AscentProgram::default()
    };
    program.run();
    let mut expected: Vec<_> = program
        .two_hop
        .iter()
        .map(|(from, to)| format!("{from}\t{to}"))
        .collect();
    expected.sort_unstable();
    for recipe in ["index-rows", "index-rows-alist"] {
        let output = scheme_output(recipe, "50\n");
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, expected, "provider recipe: {recipe}");
    }
}

#[test]
fn indexed_composite_group_and_node_join_matches_ascent() {
    ascent! {
        relation edge(u32, u32, u32);
        relation two_hop(u32, u32, u32);
        two_hop(group, from, to) <--
            edge(group, from, via), edge(group, via, to);
    }
    let edges: Vec<_> = (0..50)
        .map(|from| (0, from, from + 1))
        .chain((0..50).map(|from| (1, from + 100, from + 101)))
        .collect();
    let mut program = AscentProgram {
        edge: edges,
        ..AscentProgram::default()
    };
    program.run();
    let mut expected: Vec<_> = program
        .two_hop
        .iter()
        .map(|(group, from, to)| format!("{group}\t{from}\t{to}"))
        .collect();
    expected.sort_unstable();
    assert_eq!(expected.len(), 98);
    for recipe in ["index-composite-rows", "index-composite-rows-alist"] {
        let output = scheme_output(recipe, "50\n");
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, expected, "provider recipe: {recipe}");
    }
}
