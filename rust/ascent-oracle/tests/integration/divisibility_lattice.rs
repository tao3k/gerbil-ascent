// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! A non-total divisibility lattice with downstream negation and count.

use super::common::scheme_output;
use ascent::{ascent, lattice::Lattice};
use std::{cmp::Ordering, collections::BTreeSet};

type Edge = (u32, u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct Divisibility(u32);

fn gcd(mut left: u32, mut right: u32) -> u32 {
    while right != 0 {
        (left, right) = (right, left % right);
    }
    left
}

fn lcm(left: u32, right: u32) -> u32 {
    left / gcd(left, right) * right
}

impl PartialOrd for Divisibility {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        match (
            other.0.is_multiple_of(self.0),
            self.0.is_multiple_of(other.0),
        ) {
            (true, true) => Some(Ordering::Equal),
            (true, false) => Some(Ordering::Less),
            (false, true) => Some(Ordering::Greater),
            (false, false) => None,
        }
    }
}

impl Lattice for Divisibility {
    fn meet_mut(&mut self, other: Self) -> bool {
        let meet = gcd(self.0, other.0);
        let changed = self.0 != meet;
        self.0 = meet;
        changed
    }

    fn join_mut(&mut self, other: Self) -> bool {
        let join = lcm(self.0, other.0);
        let changed = self.0 != join;
        self.0 = join;
        changed
    }
}

fn edges_for(mask: u32) -> Vec<Edge> {
    (0..3)
        .flat_map(|from| (0..3).map(move |to| (from, to)))
        .enumerate()
        .filter_map(|(bit, edge)| (mask & (1 << bit) != 0).then_some(edge))
        .collect()
}

fn rust_rows(edges: &[Edge]) -> BTreeSet<String> {
    ascent! {
        relation edge(u32, u32);
        relation seed(u32, u32);
        relation root(u32);
        lattice spectrum(u32, Divisibility);
        relation six(u32);
        relation not_six(u32);
        relation six_count(usize);

        spectrum(node, Divisibility(*value)) <-- seed(node, value);
        spectrum(to, value.clone()) <-- spectrum(from, ?value), edge(from, to);
        six(node) <-- spectrum(node, ?Divisibility(value)), if *value % 6 == 0;
        not_six(node) <-- root(node), !six(node);
        six_count(total) <-- agg total = ascent::aggregators::count() in six(_);
    }
    let mut program = AscentProgram {
        edge: edges.to_vec(),
        seed: vec![(0, 2), (1, 3), (2, 5)],
        root: vec![(0,), (1,), (2,)],
        ..AscentProgram::default()
    };
    program.run();
    program
        .spectrum
        .iter()
        .map(|(node, Divisibility(value))| format!("spectrum\t{node}\t{value}"))
        .chain(program.six.iter().map(|(node,)| format!("six\t{node}")))
        .chain(
            program
                .not_six
                .iter()
                .map(|(node,)| format!("not-six\t{node}")),
        )
        .chain(
            program
                .six_count
                .iter()
                .map(|(total,)| format!("six-count\t{total}")),
        )
        .collect()
}

fn model_rows(edges: &[Edge]) -> BTreeSet<String> {
    let mut reach = [[false; 3]; 3];
    for (node, targets) in reach.iter_mut().enumerate() {
        targets[node] = true;
    }
    for &(from, to) in edges {
        reach[from as usize][to as usize] = true;
    }
    for via in 0..3 {
        for from in 0..3 {
            for to in 0..3 {
                reach[from][to] |= reach[from][via] && reach[via][to];
            }
        }
    }
    let seeds = [2, 3, 5];
    let mut rows = BTreeSet::new();
    let mut count = 0;
    for (node, _) in reach.iter().enumerate() {
        let value = (0..3)
            .filter(|source| reach[*source][node])
            .map(|source| seeds[source])
            .reduce(lcm)
            .expect("each node has its own seed");
        rows.insert(format!("spectrum\t{node}\t{value}"));
        if value % 6 == 0 {
            rows.insert(format!("six\t{node}"));
            count += 1;
        } else {
            rows.insert(format!("not-six\t{node}"));
        }
    }
    rows.insert(format!("six-count\t{count}"));
    rows
}

#[test]
fn divisibility_join_feeds_negative_and_aggregate_strata() {
    let request = format!(
        "({})\n",
        (0..512)
            .map(|mask| {
                let edges = edges_for(mask)
                    .iter()
                    .map(|(from, to)| format!("({from} {to})"))
                    .collect::<Vec<_>>()
                    .join(" ");
                format!("({mask} ({edges}))")
            })
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("divisibility-lattice-rows", &request);
    let mut scheme = output.lines().map(str::to_owned).collect::<Vec<_>>();
    assert_eq!(scheme.pop().as_deref(), Some("END"));
    let scheme = scheme.into_iter().collect::<BTreeSet<_>>();
    let mut expected = BTreeSet::new();
    for mask in 0..512 {
        let edges = edges_for(mask);
        let rust = rust_rows(&edges);
        let model = model_rows(&edges);
        assert_eq!(rust, model, "Rust mask={mask}");
        expected.extend(rust.into_iter().map(|row| format!("{mask}\t{row}")));
    }
    assert_eq!(scheme, expected);
}
