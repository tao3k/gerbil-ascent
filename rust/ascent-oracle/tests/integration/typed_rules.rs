// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Typed rules, repeated variables and clause forms.

use super::common::scheme_output;
use ascent::ascent;

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
        relation dependent(u32, u32);
        relation successor(u32, u32);
        relation blocked(u32, u32);
        relation allowed(u32, u32);
        relation denied(u32, u32);
        relation safe_reach(u32, u32);
        relation reach(u32, u32);

        labelled(x, z, first.clone(), second.clone()) <--
            edge(x, y, first), edge(y, z, second);
        cycle(x) <-- edge(x, y, _), if x == y;
        hot(x), selected(x, y) <-- edge(x, y, label), if label.as_str() == "a";
        choice(x, y) <-- node(x), for y in 1..=3, if *x != y;
        generated(x) <-- for x in 1..=3;
        dependent(x, y) <-- node(x), for y in 0..(*x - 1);
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
            .dependent
            .iter()
            .map(|(from, to)| format!("dependent\t{from}\t{to}")),
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
