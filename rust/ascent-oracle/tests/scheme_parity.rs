// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Independent Rust Ascent oracle for POO Flow's Scheme qualification fixtures.

use ascent::aggregators::{count, max, mean, min, sum};
use ascent::{ascent, ascent_run, Dual};
use ascent_byods_rels::{eqrel, trrel, trrel_uf};
use std::{
    cmp::Reverse,
    collections::{BTreeSet, BinaryHeap},
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("gerbil-ascent repository root")
        .to_path_buf()
}

fn scheme_output(recipe: &str, request: &str) -> String {
    let root = root();
    let mut command = Command::new("just");
    command
        .current_dir(&root)
        .arg(recipe)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let gerbil_path =
        std::env::var_os("GERBIL_PATH").unwrap_or_else(|| root.join(".gerbil").into());
    let inherited = std::env::var("GERBIL_LOADPATH").unwrap_or_default();
    command.env("GERBIL_PATH", gerbil_path);
    command.env("GERBIL_LOADPATH", format!("{}:{inherited}", root.display()));
    let mut child = command
        .spawn()
        .expect("launch gerbil-ascent Scheme fixture");
    child
        .stdin
        .take()
        .expect("Scheme fixture stdin")
        .write_all(request.as_bytes())
        .expect("write Scheme fixture request");
    let output = child
        .wait_with_output()
        .expect("collect Scheme fixture output");
    assert!(
        output.status.success(),
        "Scheme fixture failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).expect("Scheme output is UTF-8")
}

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

fn scheme_pairs(edges: &[(u32, u32)], generic: bool) -> Vec<(u32, u32)> {
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

fn positive_request(edges: &[(u32, u32, &str)]) -> String {
    let mut request = String::from("(");
    for &(from, to, label) in edges {
        request.push_str(&format!(" ({from} {to} \"{label}\")"));
    }
    request.push_str(")\n");
    request
}

fn ascent_positive_rows(edges: &[(u32, u32, &str)]) -> Vec<String> {
    ascent! {
        relation edge(u32, u32, String);
        relation node(u32);
        relation labelled(u32, u32, String, String);
        relation cycle(u32);
        relation hot(u32);
        relation selected(u32, u32);
        relation choice(u32, u32);
        relation generated(u32);
        relation successor(u32, u32);
        relation blocked(u32, u32);
        relation allowed(u32, u32);
        relation denied(u32, u32);
        relation safe_reach(u32, u32);
        relation reach(u32, u32);

        labelled(x, z, first.clone(), second.clone()) <--
            edge(x, y, first), edge(y, z, second);
        cycle(x) <-- edge(x, x, _);
        hot(x), selected(x, y) <-- edge(x, y, label), if label.as_str() == "a";
        choice(x, y) <-- node(x), for y in 1..=3, if *x != y;
        generated(x) <-- for x in 1..=3;
        successor(x, y) <-- node(x), let y = *x + 1;
        blocked(x, y) <-- edge(x, y, label), if label.as_str() == "c";
        allowed(x, y) <-- edge(x, y, _), !blocked(x, y);
        denied(x, y) <-- edge(x, y, _), !allowed(x, y);
        safe_reach(x, y) <-- allowed(x, y);
        safe_reach(x, z) <-- safe_reach(x, y), allowed(y, z);
        reach(x, y) <-- edge(x, y, _);
        reach(x, z) <-- reach(x, y), edge(y, z, _);
    }
    let mut program = AscentProgram {
        edge: edges
            .iter()
            .map(|&(from, to, label)| (from, to, label.to_owned()))
            .collect(),
        node: vec![(1,), (2,), (3,)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .labelled
            .iter()
            .map(|(from, to, first, second)| format!("labelled\t{from}\t{to}\t{first}\t{second}")),
    );
    rows.extend(program.cycle.iter().map(|(node,)| format!("cycle\t{node}")));
    rows.extend(program.hot.iter().map(|(node,)| format!("hot\t{node}")));
    rows.extend(
        program
            .selected
            .iter()
            .map(|(from, to)| format!("selected\t{from}\t{to}")),
    );
    rows.extend(
        program
            .choice
            .iter()
            .map(|(from, to)| format!("choice\t{from}\t{to}")),
    );
    rows.extend(
        program
            .generated
            .iter()
            .map(|(value,)| format!("generated\t{value}")),
    );
    rows.extend(
        program
            .successor
            .iter()
            .map(|(from, to)| format!("successor\t{from}\t{to}")),
    );
    rows.extend(
        program
            .blocked
            .iter()
            .map(|(from, to)| format!("blocked\t{from}\t{to}")),
    );
    rows.extend(
        program
            .allowed
            .iter()
            .map(|(from, to)| format!("allowed\t{from}\t{to}")),
    );
    rows.extend(
        program
            .denied
            .iter()
            .map(|(from, to)| format!("denied\t{from}\t{to}")),
    );
    rows.extend(
        program
            .safe_reach
            .iter()
            .map(|(from, to)| format!("safe-reach\t{from}\t{to}")),
    );
    rows.extend(
        program
            .reach
            .iter()
            .map(|(from, to)| format!("reach\t{from}\t{to}")),
    );
    rows.sort_unstable();
    rows
}

#[test]
fn arbitrary_relation_columns_and_repeated_variables_match_ascent() {
    let snapshots: &[&[(u32, u32, &str)]] = &[
        &[],
        &[(1, 2, "a"), (2, 3, "b"), (3, 3, "c")],
        &[(1, 2, "a"), (2, 3, "b"), (3, 3, "c"), (1, 2, "a")],
        &[(1, 2, "a"), (3, 3, "c")],
    ];
    for edges in snapshots {
        let output = scheme_output("rule-rows", &positive_request(edges));
        let lines: Vec<_> = output.lines().collect();
        assert_eq!(lines.last(), Some(&"END"), "Scheme fixture did not finish");
        let mut scheme: Vec<_> = lines[..lines.len() - 1]
            .iter()
            .map(|line| (*line).to_owned())
            .collect();
        scheme.sort_unstable();
        assert_eq!(scheme, ascent_positive_rows(edges), "edges: {edges:?}");
    }
}

fn extrema<'a>(input: impl Iterator<Item = (&'a i32,)>) -> impl Iterator<Item = i32> {
    let values: Vec<_> = input.map(|(value,)| *value).collect();
    values
        .iter()
        .min()
        .copied()
        .into_iter()
        .chain(values.iter().max().copied())
}

fn ascent_aggregate_rows(values: &[i32]) -> Vec<String> {
    ascent! {
        relation number(i32);
        relation group_key(u32);
        relation pair(u32, i32);
        relation by_group(u32, i32);
        relation minimum(i32);
        relation maximum(i32);
        relation total(i32);
        relation cardinality(usize);
        relation average(i32);
        relation custom(i32);
        minimum(value) <-- agg value = min(x) in number(x);
        maximum(value) <-- agg value = max(x) in number(x);
        total(value) <-- agg value = sum(x) in number(x);
        cardinality(value) <-- agg value = count() in number(_);
        average(value.round() as i32) <-- agg value = mean(x) in number(x);
        custom(value) <-- agg value = extrema(x) in number(x);
        by_group(group, total) <-- group_key(group), agg total = sum(x) in pair(group, x);
    }
    let mut program = AscentProgram {
        number: values.iter().copied().map(|value| (value,)).collect(),
        group_key: vec![(1,), (2,)],
        pair: vec![(1, 10), (1, 20), (2, 5)],
        ..AscentProgram::default()
    };
    program.run();
    let mut rows = Vec::new();
    rows.extend(
        program
            .by_group
            .iter()
            .map(|(group, total)| format!("by-group\t{group}\t{total}")),
    );
    rows.extend(
        program
            .minimum
            .iter()
            .map(|(value,)| format!("minimum\t{value}")),
    );
    rows.extend(
        program
            .maximum
            .iter()
            .map(|(value,)| format!("maximum\t{value}")),
    );
    rows.extend(
        program
            .total
            .iter()
            .map(|(value,)| format!("total\t{value}")),
    );
    rows.extend(
        program
            .cardinality
            .iter()
            .map(|(value,)| format!("cardinality\t{value}")),
    );
    rows.extend(
        program
            .average
            .iter()
            .map(|(value,)| format!("average\t{value}")),
    );
    rows.extend(
        program
            .custom
            .iter()
            .map(|(value,)| format!("custom\t{value}")),
    );
    rows.sort_unstable();
    rows
}

#[test]
fn builtin_and_custom_aggregators_match_ascent() {
    for values in [&[][..], &[1, 2, 3, 4, 5][..], &[5, 2, 5, 1][..]] {
        let request = format!(
            "({})\n",
            values
                .iter()
                .map(i32::to_string)
                .collect::<Vec<_>>()
                .join(" ")
        );
        let output = scheme_output("aggregate-rows", &request);
        let mut rows: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(rows.pop().as_deref(), Some("END"));
        rows.sort_unstable();
        assert_eq!(rows, ascent_aggregate_rows(values), "values: {values:?}");
    }
}

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

fn ascent_eqrel_rows(binary: &[(u32, u32)], grouped: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation binary_seed(u32, u32);
        relation grouped_seed(u32, u32, u32);
        #[ds(eqrel)]
        relation binary_eq(u32, u32);
        #[ds(eqrel)]
        relation grouped_eq(u32, u32, u32);
        relation binary_output(u32, u32);
        relation grouped_output(u32, u32, u32);
        binary_eq(x, y) <-- binary_seed(x, y);
        grouped_eq(g, x, y) <-- grouped_seed(g, x, y);
        binary_output(x, y) <-- binary_eq(x, y);
        grouped_output(g, x, y) <-- grouped_eq(g, x, y);
    }
    let mut program = AscentProgram {
        binary_seed: binary.to_vec(),
        grouped_seed: grouped.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .binary_output
        .iter()
        .map(|(x, y)| format!("binary-output\t{x}\t{y}"))
        .chain(
            program
                .grouped_output
                .iter()
                .map(|(g, x, y)| format!("grouped-output\t{g}\t{x}\t{y}")),
        )
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn binary_and_grouped_eqrel_match_ascent_byods() {
    let snapshots: &[(Vec<(u32, u32)>, Vec<(u32, u32, u32)>)] = &[
        (vec![], vec![]),
        (vec![(1, 2)], vec![(0, 3, 4)]),
        (vec![(1, 2), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        (
            vec![(1, 2), (3, 4), (2, 3), (1, 2)],
            vec![(0, 1, 2), (0, 2, 3), (1, 4, 5)],
        ),
    ];
    for (binary, grouped) in snapshots {
        let binary_request = binary
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let grouped_request = grouped
            .iter()
            .map(|(g, x, y)| format!("({g} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({binary_request}) ({grouped_request}))\n");
        let output = scheme_output("eqrel-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_eqrel_rows(binary, grouped));
    }
}

fn ascent_trrel_rows(binary: &[(u32, u32)], grouped: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation binary_seed(u32, u32);
        relation grouped_seed(u32, u32, u32);
        #[ds(trrel)]
        relation binary_tr(u32, u32);
        #[ds(trrel)]
        relation grouped_tr(u32, u32, u32);
        relation binary_output(u32, u32);
        relation grouped_output(u32, u32, u32);
        binary_tr(x, y) <-- binary_seed(x, y);
        grouped_tr(g, x, y) <-- grouped_seed(g, x, y);
        binary_output(x, y) <-- binary_tr(x, y);
        grouped_output(g, x, y) <-- grouped_tr(g, x, y);
    }
    let mut program = AscentProgram {
        binary_seed: binary.to_vec(),
        grouped_seed: grouped.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .binary_output
        .iter()
        .map(|(x, y)| format!("binary-output\t{x}\t{y}"))
        .chain(
            program
                .grouped_output
                .iter()
                .map(|(g, x, y)| format!("grouped-output\t{g}\t{x}\t{y}")),
        )
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn binary_and_grouped_trrel_match_ascent_byods() {
    let snapshots: &[(Vec<(u32, u32)>, Vec<(u32, u32, u32)>)] = &[
        (vec![], vec![]),
        (vec![(1, 1)], vec![(0, 2, 2)]),
        (vec![(1, 2)], vec![(0, 3, 4)]),
        (vec![(1, 2), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        (vec![(1, 2), (2, 3), (3, 1)], vec![(0, 1, 2), (0, 2, 1)]),
        (vec![(1, 2), (3, 4), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
    ];
    for (binary, grouped) in snapshots {
        let binary_request = binary
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let grouped_request = grouped
            .iter()
            .map(|(g, x, y)| format!("({g} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({binary_request}) ({grouped_request}))\n");
        let output = scheme_output("trrel-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_trrel_rows(binary, grouped));
    }
}

fn ascent_trrel_uf_rows(binary: &[(u32, u32)], grouped: &[(u32, u32, u32)]) -> Vec<String> {
    ascent! {
        relation binary_seed(u32, u32);
        relation grouped_seed(u32, u32, u32);
        #[ds(trrel_uf)]
        relation binary_tr(u32, u32);
        #[ds(trrel_uf)]
        relation grouped_tr(u32, u32, u32);
        relation binary_output(u32, u32);
        relation grouped_output(u32, u32, u32);
        binary_tr(x, y) <-- binary_seed(x, y);
        grouped_tr(g, x, y) <-- grouped_seed(g, x, y);
        binary_output(x, y) <-- binary_tr(x, y);
        grouped_output(g, x, y) <-- grouped_tr(g, x, y);
    }
    let mut program = AscentProgram {
        binary_seed: binary.to_vec(),
        grouped_seed: grouped.to_vec(),
        ..AscentProgram::default()
    };
    program.run();
    let mut rows: Vec<_> = program
        .binary_output
        .iter()
        .map(|(x, y)| format!("binary-output\t{x}\t{y}"))
        .chain(
            program
                .grouped_output
                .iter()
                .map(|(g, x, y)| format!("grouped-output\t{g}\t{x}\t{y}")),
        )
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn binary_and_grouped_trrel_uf_match_ascent_byods() {
    let snapshots: &[(Vec<(u32, u32)>, Vec<(u32, u32, u32)>)] = &[
        (vec![], vec![]),
        (vec![(1, 1)], vec![(0, 2, 2)]),
        (vec![(1, 2)], vec![(0, 3, 4)]),
        (vec![(1, 2), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
        (vec![(1, 2), (2, 3), (3, 1)], vec![(0, 1, 2), (0, 2, 1)]),
        (vec![(1, 2), (3, 4), (2, 3)], vec![(0, 1, 2), (1, 2, 3)]),
    ];
    for (binary, grouped) in snapshots {
        let binary_request = binary
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let grouped_request = grouped
            .iter()
            .map(|(g, x, y)| format!("({g} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({binary_request}) ({grouped_request}))\n");
        let output = scheme_output("trrel-uf-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_trrel_uf_rows(binary, grouped));
    }
}

#[test]
fn grouped_byods_join_with_string_keys_matches_ascent() {
    ascent! {
        relation seed(String, u32, u32);
        relation seed_extra(String, u32, u32);
        relation wanted(String, u32);
        #[ds(eqrel)]
        relation eq(String, u32, u32);
        #[ds(trrel)]
        relation tr(String, u32, u32);
        #[ds(trrel_uf)]
        relation uf(String, u32, u32);
        relation eq_match(String, u32, u32);
        relation tr_match(String, u32, u32);
        relation uf_match(String, u32, u32);
        eq(g, x, y) <-- seed(g, x, y);
        tr(g, x, y) <-- seed(g, x, y);
        uf(g, x, y) <-- seed(g, x, y);
        eq(g, x, y) <-- seed_extra(g, x, y);
        tr(g, x, y) <-- seed_extra(g, x, y);
        uf(g, x, y) <-- seed_extra(g, x, y);
        eq_match(g, x, y) <-- eq(g, x, y), wanted(g, y);
        tr_match(g, x, y) <-- tr(g, x, y), wanted(g, y);
        uf_match(g, x, y) <-- uf(g, x, y), wanted(g, y);
    }
    for (seed, seed_extra, wanted) in [
        (vec![], vec![], vec![]),
        (
            vec![
                ("alpha".to_owned(), 1, 2),
                ("alpha".to_owned(), 2, 3),
                ("beta".to_owned(), 1, 2),
            ],
            vec![],
            vec![("alpha".to_owned(), 3), ("beta".to_owned(), 2)],
        ),
        (
            vec![("alpha".to_owned(), 1, 2), ("alpha".to_owned(), 2, 1)],
            vec![],
            vec![("alpha".to_owned(), 1)],
        ),
        (
            vec![("alpha".to_owned(), 1, 2), ("beta".to_owned(), 1, 2)],
            vec![("alpha".to_owned(), 2, 3), ("beta".to_owned(), 2, 1)],
            vec![("alpha".to_owned(), 3), ("beta".to_owned(), 1)],
        ),
    ] {
        let mut program = AscentProgram {
            seed: seed.clone(),
            seed_extra: seed_extra.clone(),
            wanted: wanted.clone(),
            ..AscentProgram::default()
        };
        program.run();
        // In 0.8.0, eqrel's grouped read after two separate producer rules
        // can drop the merged alpha component. A single producer over the
        // same facts supplies the mathematical equivalence baseline instead.
        let mut combined = AscentProgram {
            seed: seed.iter().chain(seed_extra.iter()).cloned().collect(),
            wanted: wanted.clone(),
            ..AscentProgram::default()
        };
        combined.run();
        let mut expected = combined
            .eq_match
            .iter()
            .map(|(g, x, y)| format!("eq-match\t{g}\t{x}\t{y}"))
            .chain(
                program
                    .tr_match
                    .iter()
                    .map(|(g, x, y)| format!("tr-match\t{g}\t{x}\t{y}")),
            )
            .chain(
                program
                    .uf_match
                    .iter()
                    .map(|(g, x, y)| format!("uf-match\t{g}\t{x}\t{y}")),
            )
            .collect::<Vec<_>>();
        expected.sort_unstable();
        let seed_request = seed
            .iter()
            .map(|(g, x, y)| format!("({g:?} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let wanted_request = wanted
            .iter()
            .map(|(g, y)| format!("({g:?} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let seed_extra_request = seed_extra
            .iter()
            .map(|(g, x, y)| format!("({g:?} {x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("(({seed_request}) ({wanted_request}) ({seed_extra_request}))\n");
        let mut actual = scheme_output("byods-query-rows", &request)
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, expected, "seed {seed:?}, wanted {wanted:?}");
    }
}

fn ascent_local_origin_rows(edges: &[(u32, u32)], origin: u32) -> Vec<String> {
    let result = ascent_run! {
        relation edge(u32, u32);
        relation reach(u32, u32);
        edge(x, y) <-- for &(x, y) in edges;
        reach(x, y) <-- edge(x, y), if *x == origin;
        reach(x, z) <-- reach(x, y), edge(y, z);
    };
    let mut rows: Vec<_> = result
        .reach
        .iter()
        .map(|(x, y)| format!("{x}\t{y}"))
        .collect();
    rows.sort_unstable();
    rows
}

#[test]
fn gerbil_module_and_lexical_origin_match_ascent_run() {
    let snapshots: &[(u32, &[(u32, u32)])] = &[
        (1, &[(1, 2), (2, 3), (3, 4), (2, 5)]),
        (2, &[(1, 2), (2, 3), (3, 4), (2, 5)]),
        (3, &[(1, 2), (2, 3), (3, 4), (4, 2)]),
        (9, &[(1, 2), (2, 3)]),
    ];
    for &(origin, edges) in snapshots {
        let source = edges
            .iter()
            .map(|(x, y)| format!("({x} {y})"))
            .collect::<Vec<_>>()
            .join(" ");
        let request = format!("({origin} ({source}))\n");
        let output = scheme_output("module-rows", &request);
        let mut actual: Vec<_> = output.lines().map(str::to_owned).collect();
        assert_eq!(actual.pop().as_deref(), Some("END"));
        actual.sort_unstable();
        assert_eq!(actual, ascent_local_origin_rows(edges, origin));
    }
}

#[test]
fn rust_repeated_run_source_update_oracle() {
    ascent! {
        relation edge(u32, u32);
        relation reach(u32, u32);
        reach(x, y) <-- edge(x, y);
        reach(x, z) <-- reach(x, y), edge(y, z);
    }
    let mut program = AscentProgram {
        edge: vec![(1, 2)],
        ..AscentProgram::default()
    };
    program.run();
    let mut first = program.reach.clone();
    first.sort_unstable();
    assert_eq!(first, vec![(1, 2)]);
    assert_eq!(scheme_pairs(&program.edge, true), first);

    program.edge.push((2, 3));
    program.run();
    let mut second = program.reach.clone();
    second.sort_unstable();
    assert_eq!(second, vec![(1, 2), (1, 3), (2, 3)]);
    assert_eq!(scheme_pairs(&program.edge, true), second);
}

#[test]
fn mutually_recursive_scc_matches_ascent() {
    ascent! {
        relation edge(u32, u32);
        relation path0(u32, u32);
        relation path1(u32, u32);
        path1(x, z) <-- path0(x, y), edge(y, z);
        path0(x, z) <-- path1(x, y), edge(y, z);
        path0(x, y) <-- edge(x, y);
    }
    for edges in [
        vec![(1, 2), (2, 3), (3, 1)],
        vec![(3, 1), (2, 3), (1, 2)],
        vec![(1, 2), (2, 3)],
    ] {
        let mut program = AscentProgram {
            edge: edges.clone(),
            ..AscentProgram::default()
        };
        program.run();
        let mut rust_rows = program
            .path0
            .iter()
            .map(|(x, y)| format!("path0\t{x}\t{y}"))
            .chain(
                program
                    .path1
                    .iter()
                    .map(|(x, y)| format!("path1\t{x}\t{y}")),
            )
            .collect::<Vec<_>>();
        rust_rows.sort();
        let request = format!(
            "({})\n",
            edges
                .iter()
                .map(|(x, y)| format!("({x} {y})"))
                .collect::<Vec<_>>()
                .join(" ")
        );
        let mut scheme_rows = scheme_output("mutual-rows", &request)
            .lines()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        scheme_rows.sort();
        assert_eq!(scheme_rows, rust_rows, "source {edges:?}");
    }
}
