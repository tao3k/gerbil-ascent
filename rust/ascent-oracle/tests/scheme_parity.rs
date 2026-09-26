// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Independent Rust Ascent oracle for POO Flow's Scheme qualification fixtures.

use ascent::aggregators::{count, max, mean, min, sum};
use ascent::{ascent, Dual};
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
