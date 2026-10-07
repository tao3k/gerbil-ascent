// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
use super::*;

// Deliberately restricted data reader: lists, names, unescaped quoted cells,
// and line comments. It cannot execute Scheme or evaluate production rules.
#[derive(Debug)]
enum Data {
    Text(String),
    List(Vec<Data>),
}
impl Data {
    fn text(&self) -> &str {
        match self {
            Self::Text(s) => s,
            _ => panic!("expected data token"),
        }
    }
    fn list(&self) -> &[Data] {
        match self {
            Self::List(xs) => xs,
            _ => panic!("expected data list"),
        }
    }
}
fn read_data(input: &mut std::iter::Peekable<std::str::Chars<'_>>) -> Data {
    loop {
        match input.peek() {
            Some(c) if c.is_whitespace() => {
                input.next();
            }
            Some(';') => {
                for c in input.by_ref() {
                    if c == '\n' {
                        break;
                    }
                }
            }
            _ => break,
        }
    }
    match input.next().expect("truncated fixture") {
        '(' => {
            let mut xs = Vec::new();
            loop {
                while input.peek().is_some_and(|c| c.is_whitespace()) {
                    input.next();
                }
                if input.peek() == Some(&')') {
                    input.next();
                    break;
                }
                xs.push(read_data(input));
            }
            Data::List(xs)
        }
        '"' => {
            let mut s = String::new();
            loop {
                let c = input.next().expect("unterminated fixture string");
                if c == '"' {
                    break;
                }
                assert_ne!(c, '\\', "fixture reader does not support escapes");
                s.push(c);
            }
            Data::Text(s)
        }
        c => {
            assert_ne!(c, ')');
            let mut s = String::from(c);
            while input
                .peek()
                .is_some_and(|c| !c.is_whitespace() && *c != ')')
            {
                s.push(input.next().unwrap());
            }
            Data::Text(s)
        }
    }
}
fn tsv(rows: &[Data]) -> String {
    rows.iter()
        .map(|row| {
            let cells: Vec<_> = row.list().iter().map(Data::text).collect();
            format!("{}\n", cells.join("\t"))
        })
        .collect()
}
#[test]
fn complete_native_controls_are_independent_naive_reference_observations() {
    let source = include_str!("../../../../t/qualification/fixtures/polonius/controls.sexp");
    let mut chars = source.chars().peekable();
    let controls = read_data(&mut chars);
    assert!(chars.all(char::is_whitespace), "trailing fixture data");
    assert_eq!(controls.list().len(), 10);
    for control in controls.list() {
        let fields = control.list();
        assert_eq!(fields.len(), 3);
        let input = tests::Inputs::empty();
        assert_eq!(fields[1].list().len(), 18);
        for relation in fields[1].list() {
            let columns = relation.list();
            input.write(columns[0].text(), &tsv(&columns[1..]));
        }
        let mut names = Names::default();
        let facts = load(&input.0, &mut names).unwrap();
        let output = Output::<Types>::compute(&facts, Algorithm::Naive, true);
        export(&output, &names, &input.0).unwrap();
        assert_eq!(fields[2].list().len(), 13);
        for relation in fields[2].list() {
            let columns = relation.list();
            let actual =
                fs::read_to_string(input.0.join(format!("{}.tsv", columns[0].text()))).unwrap();
            assert_eq!(
                actual,
                tsv(&columns[1..]),
                "{} / {}",
                fields[0].text(),
                columns[0].text()
            );
        }
        // This upstream inspection field is not one of the thirteen truths.
        assert!(output.loan_invalidated_at.is_empty());
    }
}
