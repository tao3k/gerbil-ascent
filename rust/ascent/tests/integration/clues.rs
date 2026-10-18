use gerbil_ascent::{
    Cancellation, ClueExchange, Data, Engine, Limits, clue_sexpr, read_clue_request,
};

#[test]
fn scheme_request_reuses_the_bounded_reader_and_never_evaluates_forms() {
    let expected = Data::object([
        ("bindings", list(&[&["arbitrary-factor", "new-hypothesis"]])),
        ("expand", Data::List(vec!["unknown-claim".into()])),
        ("checkpoint", "clue-read:opaque".into()),
    ]);
    assert_eq!(read_clue_request(&clue_sexpr(&expected)).unwrap(), expected);
    assert_eq!(
        read_clue_request("((questions (\"a\" \"b\")))").unwrap(),
        Data::object([("questions", Data::List(vec!["a".into(), "b".into()]))])
    );
    for rejected in [
        "((checkpoint \"a\") (checkpoint \"b\"))",
        "((unknownField \"value\"))",
        "((bindings (system \"command\")))",
        "(begin (display \"not data\"))",
        "((bindings ())) ((expand ()))",
        "((questions 2))",
        "((bindings ((\"name\"))))",
        "((displayBytes 0))",
        "((constructor \"ignored\"))",
    ] {
        assert!(read_clue_request(rejected).is_err(), "{rejected}");
    }
}

const PROJECTION: &str = r#"
(define-evidence (project)
 (sources clue factor link) (outputs clue factor link)
 (relation clue (id digest claim polarity role source))
 (relation factor (id digest name value))
 (relation link (claim target label id digest)))
(define-evidence (select)
 (sources clue factor binding) (outputs question)
 (relation clue (id digest claim polarity role source))
 (relation factor (id digest name value))
 (relation binding (name value))
 (relation question (claim))
 ((question C) <-- (clue I D C _ _ _) (factor I D N V) (binding N V)))
"#;

fn list(rows: &[&[&str]]) -> Data {
    Data::List(
        rows.iter()
            .map(|r| Data::List(r.iter().map(|v| (*v).into()).collect()))
            .collect(),
    )
}
fn facts() -> Data {
    Data::object([
        (
            "clue",
            list(&[&[
                "known",
                "sha",
                "old-is-unexplored",
                "counter",
                "observation",
                "receipt",
            ]]),
        ),
        ("factor", list(&[&["known", "sha", "mechanism", "old"]])),
        (
            "link",
            list(&[&[
                "old-is-unexplored",
                "open",
                "not-same-cause",
                "known",
                "sha",
            ]]),
        ),
    ])
}
fn exchange(engine: &Engine) -> ClueExchange {
    ClueExchange::new(
        engine,
        &[PROJECTION],
        "project",
        &facts(),
        &Data::object([("receipt", "sha".into())]),
        &Limits::default(),
        &Cancellation::default(),
    )
    .unwrap()
}

// Association and applicability are caller-owned DSL, not host heuristics.
#[test]
fn wide_scope_pages_without_acknowledging_grouped_references() {
    let engine = Engine::new(1).unwrap();
    let claims = (0..96).map(|i| format!("claim-{i:03}")).collect::<Vec<_>>();
    let mut witnesses = Vec::new();
    for claim in &claims {
        for polarity in ["support", "counter"] {
            witnesses.push(Data::List(vec![
                format!("{claim}-{polarity}").into(),
                "sha".into(),
                claim.clone().into(),
                polarity.into(),
                "observation".into(),
                "receipt".into(),
            ]));
        }
    }
    let input = Data::object([
        ("clue", Data::List(witnesses)),
        ("factor", Data::List(vec![])),
        ("link", Data::List(vec![])),
    ]);
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let mut owner = ClueExchange::new(
        &engine,
        &[PROJECTION],
        "project",
        &input,
        &Data::object([("receipt", "sha".into())]),
        &limits,
        &cancel,
    )
    .unwrap();
    let mut request = Data::object([
        (
            "questions",
            Data::List(claims.iter().cloned().map(Data::from).collect()),
        ),
        ("displayBytes", 8192usize.into()),
    ])
    .map()
    .unwrap()
    .clone();
    let mut seen = std::collections::BTreeSet::new();
    let mut complete = false;
    let mut grouped = false;
    for _ in 0..=claims.len() {
        let result = owner
            .slice(&Data::Map(request.clone()), &limits, &cancel)
            .unwrap();
        let brief = result.field("brief").unwrap();
        assert!(clue_sexpr(brief).len() <= 8192);
        grouped |= brief.map().unwrap().contains_key("deferredScope");
        let page = brief.field("families").unwrap().list().unwrap();
        for family in page {
            assert!(seen.insert(family.field("claim").unwrap().text().unwrap().to_owned()));
            assert_eq!(
                family.field("observations").unwrap().list().unwrap().len(),
                2
            );
        }
        if brief.field("presentationComplete").unwrap() == &Data::Bool(true) {
            complete = true;
            break;
        }
        assert!(
            !page.is_empty(),
            "a complete family fits but the read made no progress"
        );
        request.insert(
            "checkpoint".into(),
            result.field("checkpoint").unwrap().clone(),
        );
    }
    assert!(grouped);
    assert!(complete);
    assert_eq!(seen, claims.into_iter().collect());
}

#[test]
fn shared_selection_schema_preserves_caller_query_and_source_immutability() {
    let engine = Engine::new(1).unwrap();
    let owner = exchange(&engine);
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let bindings = list(&[&["mechanism", "old"]]);
    let source = r#"(define-evidence (shared-select)
      (sources clue factor binding) (outputs question)
      (include clue-selection-schema)
      (relation question (claim))
      ((question C) <-- (clue I D C _ _ _) (factor I D N V) (binding N V)))"#;
    let explicit = owner
        .select(&[PROJECTION], "select", &bindings, &limits, &cancel)
        .unwrap();
    let shared = owner
        .select(&[source], "shared-select", &bindings, &limits, &cancel)
        .unwrap();
    assert_eq!(shared, explicit);
    let invalid = source.replace(
        "(relation question (claim))",
        "(relation question (claim)) ((clue I D C P R S) <-- (clue I D C P R S))",
    );
    assert!(
        owner
            .select(&[&invalid], "shared-select", &bindings, &limits, &cancel)
            .is_err()
    );
    assert_eq!(
        owner
            .select(&[source], "shared-select", &bindings, &limits, &cancel)
            .unwrap(),
        explicit
    );
}

const ANCHORED_SELECTOR: &str = r#"
(define-evidence (anchored)
 (sources clue factor binding)
 (outputs question associated association_gap applicability_gap)
 (relation clue (id digest claim polarity role source))
 (relation factor (id digest name value))
 (relation binding (name value))
 (relation associated (claim))
 (relation applicable (claim))
 (relation question (claim))
 (relation has_association (name value))
 (relation association_gap (name value))
 (relation applicability_gap (claim))
 ((associated C) <-- (clue I D C _ _ _) (factor I D N V) (binding N V))
 ((applicable C) <-- (clue I D C _ _ _)
   (factor I D (lit "condition") (lit "current")))
 ((question C) <-- (associated C) (applicable C))
 ((has_association N V) <-- (clue I D C _ _ _) (factor I D N V) (binding N V))
 ((association_gap N V) <-- (binding N V) (not (has_association N V)))
 ((applicability_gap C) <-- (associated C) (not (applicable C))))
"#;

#[test]
fn factor_conjunction_keeps_witness_identity_and_explains_incompatible_anchors() {
    let engine = Engine::new(1).unwrap();
    let owner = anchored_exchange(&engine, "current");
    let selector = r#"(define-evidence (query)
      (sources clue factor binding)
      (outputs question matched unknown_binding conjunction_gap)
      (include clue-selection-schema)
      (relation question (claim))
      (relation matched (claim id digest role))
      (relation missing (id digest))
      (relation witnessed (id digest name value))
      (relation has_binding (name))
      (relation has_match (name value))
      (relation matched_binding (name value))
      (relation unknown_binding (name value))
      (relation conjunction_gap (name value))
      ((has_binding N) <-- (binding N _))
      ((witnessed I D N V) <-- (factor I D N V) (binding N V))
      ((missing I D) <-- (clue I D _ _ _ _) (binding N V)
        (not (witnessed I D N V)))
      ((matched C I D R) <-- (has_binding _) (clue I D C _ R _)
        (not (missing I D)))
      ((question C) <-- (matched C _ _ _))
      ((has_match N V) <-- (clue I D _ _ _ _) (factor I D N V) (binding N V))
      ((unknown_binding N V) <-- (binding N V) (not (has_match N V)))
      ((matched_binding N V) <-- (matched _ I D _) (factor I D N V) (binding N V))
      ((conjunction_gap N V) <-- (has_match N V) (not (matched_binding N V))))"#;
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let matched = owner
        .select(
            &[selector],
            "query",
            &list(&[&["mechanism", "publication"], &["condition", "current"]]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert_eq!(matched.field("question").unwrap(), &list(&[&["header"]]));
    assert_eq!(
        matched.field("matched").unwrap(),
        &list(&[&["header", "yes", "a", "observation"]])
    );
    assert_eq!(matched.field("unknown_binding").unwrap(), &list(&[]));
    assert_eq!(matched.field("conjunction_gap").unwrap(), &list(&[]));
    // An unknown value is a gap, not evidence of absence.
    let split = owner
        .select(
            &[selector],
            "query",
            &list(&[
                &["mechanism", "publication"],
                &["condition", "current"],
                &["condition", "missing"],
            ]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert_eq!(split.field("question").unwrap(), &list(&[]));
    assert_eq!(
        split.field("unknown_binding").unwrap(),
        &list(&[&["condition", "missing"]])
    );
    assert_eq!(
        split
            .field("conjunction_gap")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        2
    );
    let input = Data::object([
        (
            "clue",
            list(&[
                &["a", "x", "same", "support", "observation", "ra"],
                &["b", "y", "same", "counter", "observation", "rb"],
            ]),
        ),
        (
            "factor",
            list(&[
                &["a", "x", "mechanism", "publication"],
                &["b", "y", "condition", "current"],
            ]),
        ),
        ("link", list(&[])),
    ]);
    let split_owner = ClueExchange::new(
        &engine,
        &[PROJECTION],
        "project",
        &input,
        &Data::object([("ra", "x".into()), ("rb", "y".into())]),
        &limits,
        &cancel,
    )
    .unwrap();
    let split = split_owner
        .select(
            &[selector],
            "query",
            &list(&[&["mechanism", "publication"], &["condition", "current"]]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert_eq!(split.field("question").unwrap(), &list(&[]));
    assert_eq!(split.field("unknown_binding").unwrap(), &list(&[]));
    assert_eq!(
        split
            .field("conjunction_gap")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        2
    );
}

fn anchored_exchange(engine: &Engine, condition: &str) -> ClueExchange {
    let input = Data::object([
        (
            "clue",
            list(&[
                &["yes", "a", "header", "support", "observation", "trace-a"],
                &["no", "b", "header", "counter", "observation", "trace-b"],
                &["far", "c", "unrelated", "support", "observation", "trace-c"],
            ]),
        ),
        (
            "factor",
            list(&[
                &["yes", "a", "mechanism", "publication"],
                &["yes", "a", "condition", condition],
            ]),
        ),
        (
            "link",
            list(&[&["header", "open-writer", "producer-unidentified", "yes", "a"]]),
        ),
    ]);
    ClueExchange::new(
        engine,
        &[PROJECTION],
        "project",
        &input,
        &Data::object([
            ("trace-a", "a".into()),
            ("trace-b", "b".into()),
            ("trace-c", "c".into()),
        ]),
        &Limits::default(),
        &Cancellation::default(),
    )
    .unwrap()
}

#[test]
fn clues_first_associated_query_returns_both_witnesses_and_trace_without_unrelated_rows() {
    let engine = Engine::new(1).unwrap();
    let mut owner = anchored_exchange(&engine, "current");
    // This is the first read: no inventory, catalog or prior selector call.
    let result = owner
        .read_selected(
            &[ANCHORED_SELECTOR],
            "anchored",
            &list(&[&["mechanism", "publication"]]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let support = result.field("support").unwrap().list().unwrap();
    let counter = result.field("counterevidence").unwrap().list().unwrap();
    assert_eq!(support.len(), 1);
    assert_eq!(counter.len(), 1);
    assert_eq!(support[0].list().unwrap()[0], Data::from("header"));
    assert_eq!(counter[0].list().unwrap()[0], Data::from("header"));
    assert_eq!(support[0].list().unwrap()[3], Data::from("trace-a"));
    assert_eq!(counter[0].list().unwrap()[3], Data::from("trace-b"));
    assert!(!support[0].list().unwrap()[4].text().unwrap().is_empty());
    assert!(!counter[0].list().unwrap()[4].text().unwrap().is_empty());
    assert_eq!(result.field("conflict").unwrap(), &list(&[&["header"]]));
    assert_eq!(result.field("neighbor").unwrap().list().unwrap().len(), 1);
    assert_eq!(result.field("unknown").unwrap(), &list(&[]));
    assert_eq!(
        result
            .field("selection")
            .unwrap()
            .field("association_gap")
            .unwrap(),
        &list(&[])
    );
    assert_eq!(
        result
            .field("selection")
            .unwrap()
            .field("applicability_gap")
            .unwrap(),
        &list(&[])
    );
}

#[test]
fn clues_unmapped_and_inapplicable_are_distinct_declared_gaps_not_absence() {
    let engine = Engine::new(1).unwrap();
    for (condition, mechanism, gap, expected) in [
        (
            "current",
            "new-factor-value",
            "association_gap",
            list(&[&["mechanism", "new-factor-value"]]),
        ),
        (
            "historical",
            "publication",
            "applicability_gap",
            list(&[&["header"]]),
        ),
    ] {
        let mut owner = anchored_exchange(&engine, condition);
        let result = owner
            .read_selected(
                &[ANCHORED_SELECTOR],
                "anchored",
                &list(&[&["mechanism", mechanism]]),
                &Limits::default(),
                &Cancellation::default(),
            )
            .unwrap();
        assert_eq!(
            result.field("selection").unwrap().field(gap).unwrap(),
            &expected
        );
        assert_eq!(result.field("support").unwrap(), &list(&[]));
        assert_eq!(result.field("counterevidence").unwrap(), &list(&[]));
        assert_eq!(result.field("unknown").unwrap(), &list(&[]));
    }
}

#[test]
fn clues_slice_first_hit_delta_collapse_and_expansion_remain_source_bound() {
    let engine = Engine::new(1).unwrap();
    let mut owner = anchored_exchange(&engine, "current");
    let request = Data::object([("bindings", list(&[&["mechanism", "publication"]]))]);
    let first = owner
        .slice_selected(
            &[ANCHORED_SELECTOR],
            "anchored",
            &request,
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let brief = first.field("brief").unwrap();
    assert_eq!(
        brief.field("counts").unwrap().field("support").unwrap(),
        &Data::from(1usize)
    );
    assert_eq!(
        brief.field("counts").unwrap().field("counter").unwrap(),
        &Data::from(1usize)
    );
    assert_eq!(brief.field("families").unwrap().list().unwrap().len(), 1);
    assert_eq!(
        brief.field("families").unwrap().list().unwrap()[0]
            .field("observations")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        2
    );
    let mut repeated = request.map().unwrap().clone();
    repeated.insert(
        "checkpoint".into(),
        first.field("checkpoint").unwrap().clone(),
    );
    let unchanged = owner
        .slice_selected(
            &[ANCHORED_SELECTOR],
            "anchored",
            &Data::Map(repeated.clone()),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(
        unchanged
            .field("brief")
            .unwrap()
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        unchanged
            .field("brief")
            .unwrap()
            .field("delta")
            .unwrap()
            .field("added")
            .unwrap(),
        &Data::from(0usize)
    );
    let capacity = clue_sexpr(brief).len() - 1;
    let mut small = request.map().unwrap().clone();
    small.insert("displayBytes".into(), capacity.into());
    let collapsed = owner
        .slice_selected(
            &[ANCHORED_SELECTOR],
            "anchored",
            &Data::Map(small),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        collapsed
            .field("brief")
            .unwrap()
            .field("presentationComplete")
            .unwrap(),
        &Data::Bool(false)
    );
    assert_eq!(
        collapsed
            .field("checkpoint")
            .unwrap()
            .field("body")
            .unwrap()
            .field("items")
            .unwrap(),
        &Data::List(vec![])
    );
    let summary = &collapsed
        .field("brief")
        .unwrap()
        .field("deferred")
        .unwrap()
        .list()
        .unwrap()[0];
    assert_eq!(
        summary.field("counts").unwrap().field("counter").unwrap(),
        &Data::from(1usize)
    );
    assert!(clue_sexpr(collapsed.field("brief").unwrap()).len() <= capacity);
    repeated.insert(
        "expand".into(),
        Data::List(vec!["unrelated".into(), "new-claim".into()]),
    );
    let expanded = owner
        .slice_selected(
            &[ANCHORED_SELECTOR],
            "anchored",
            &Data::Map(repeated),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        expanded.field("brief").unwrap().field("mode").unwrap(),
        &Data::from("rescope")
    );
    assert_eq!(
        expanded
            .field("brief")
            .unwrap()
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        2
    );
    let mut invalid = request.map().unwrap().clone();
    invalid.insert(
        "checkpoint".into(),
        Data::object([
            (
                "body",
                first
                    .field("checkpoint")
                    .unwrap()
                    .field("body")
                    .unwrap()
                    .clone(),
            ),
            ("digest", "changed".into()),
        ]),
    );
    assert!(
        owner
            .slice_selected(
                &[ANCHORED_SELECTOR],
                "anchored",
                &Data::Map(invalid),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );
}

#[test]
fn folded_reads_advance_per_family_and_rescoping_keeps_acknowledged_details() {
    let engine = Engine::new(1).unwrap();
    let mut owner = anchored_exchange(&engine, "current");
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let all = Data::object([(
        "questions",
        Data::List(vec!["header".into(), "unrelated".into()]),
    )]);
    let full = owner.slice(&all, &limits, &cancel).unwrap();
    let mut paged = all.map().unwrap().clone();
    paged.insert(
        "displayBytes".into(),
        (clue_sexpr(full.field("brief").unwrap()).len() - 1).into(),
    );
    let first = owner
        .slice(&Data::Map(paged.clone()), &limits, &cancel)
        .unwrap();
    let brief = first.field("brief").unwrap();
    let shown = brief.field("families").unwrap().list().unwrap();
    assert_eq!(shown.len(), 1);
    assert_eq!(brief.field("deferred").unwrap().list().unwrap().len(), 1);
    assert_eq!(
        brief.field("presentationComplete").unwrap(),
        &Data::Bool(false)
    );
    let first_claim = shown[0].field("claim").unwrap().clone();
    let checkpoint = first.field("checkpoint").unwrap().clone();
    assert!(
        !checkpoint
            .field("body")
            .unwrap()
            .field("items")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    paged.insert("checkpoint".into(), checkpoint);
    let second = owner.slice(&Data::Map(paged), &limits, &cancel).unwrap();
    let second_brief = second.field("brief").unwrap();
    let newly_shown = second_brief.field("families").unwrap().list().unwrap();
    assert_eq!(newly_shown.len(), 1);
    assert_ne!(newly_shown[0].field("claim").unwrap(), &first_claim);
    assert_eq!(
        second_brief.field("presentationComplete").unwrap(),
        &Data::Bool(true)
    );
    let mut shrink = Data::object([("questions", Data::List(vec![first_claim]))])
        .map()
        .unwrap()
        .clone();
    shrink.insert(
        "checkpoint".into(),
        second.field("checkpoint").unwrap().clone(),
    );
    let smaller = owner.slice(&Data::Map(shrink), &limits, &cancel).unwrap();
    let smaller_brief = smaller.field("brief").unwrap();
    assert_eq!(smaller_brief.field("mode").unwrap(), &Data::from("rescope"));
    assert!(
        smaller_brief
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        smaller_brief
            .field("delta")
            .unwrap()
            .field("removed")
            .unwrap(),
        &Data::from(0usize)
    );
    let mut widen = all.map().unwrap().clone();
    widen.insert(
        "checkpoint".into(),
        smaller.field("checkpoint").unwrap().clone(),
    );
    let repeated = owner
        .slice(&Data::Map(widen.clone()), &limits, &cancel)
        .unwrap();
    assert!(
        repeated
            .field("brief")
            .unwrap()
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    // A source change still resets acknowledgement; history is not current evidence.
    let mut changed = anchored_exchange(&engine, "changed");
    let reset = changed.slice(&Data::Map(widen), &limits, &cancel).unwrap();
    assert_eq!(
        reset.field("brief").unwrap().field("mode").unwrap(),
        &Data::from("reset")
    );
    assert_eq!(
        reset
            .field("brief")
            .unwrap()
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn clues_model_authored_relational_query_joins_edges_receipts_and_counterwitnesses() {
    let engine = Engine::new(1).unwrap();
    let mut owner = anchored_exchange(&engine, "current");
    let declaration = r#"
    (define-evidence (query)
      (sources clue factor link attested binding) (outputs question trace)
      (relation clue (id digest claim polarity role source))
      (relation factor (id digest name value))
      (relation link (from to label id digest))
      (relation attested (id digest receipt))
      (relation binding (name value))
      (relation question (claim))
      (relation trace (claim target witness digest receipt))
      ((trace C Target I D R) <-- (link C Target (lit "producer-unidentified") I D)
        (attested I D R) (factor I D (lit "condition") (lit "current"))
        (clue J H C (lit "counter") (lit "observation") S) (attested J H Other))
      ((question C) <-- (trace C _ _ _ _)))
    "#;
    let result = owner
        .slice_selected(
            &[declaration],
            "query",
            &Data::object([("bindings", Data::List(vec![]))]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let brief = result.field("brief").unwrap();
    assert_eq!(brief.field("families").unwrap().list().unwrap().len(), 1);
    assert_eq!(
        brief
            .field("association")
            .unwrap()
            .field("trace")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        brief.field("counts").unwrap().field("counter").unwrap(),
        &Data::from(1usize)
    );
}

#[test]
fn clues_derived_relations_fold_and_reuse_the_same_read_checkpoint() {
    let engine = Engine::new(1).unwrap();
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let mut supplied = facts().map().unwrap().clone();
    supplied.insert(
        "factor".into(),
        Data::List(
            (0..16)
                .map(|i| {
                    Data::List(vec![
                        "known".into(),
                        "sha".into(),
                        format!("facet-{i}").into(),
                        format!("value-{i:064}").into(),
                    ])
                })
                .collect(),
        ),
    );
    let mut owner = ClueExchange::new(
        &engine,
        &[PROJECTION],
        "project",
        &Data::Map(supplied),
        &Data::object([("receipt", "sha".into())]),
        &limits,
        &cancel,
    )
    .unwrap();
    let source = r#"(define-evidence (query)
      (sources clue factor attested) (outputs question trace)
      (include clue-selection-schema)
      (relation question (claim))
      (relation trace (claim left right))
      ((question C) <-- (clue I D C _ _ _) (attested I D _))
      ((trace C A B) <-- (clue I D C _ _ _) (attested I D _)
        (factor I D _ A) (factor I D _ B)))"#;
    let request = Data::object([("bindings", Data::List(vec![]))]);
    let first = owner
        .slice_selected(&[source], "query", &request, &limits, &cancel)
        .unwrap();
    let brief = first.field("brief").unwrap();
    assert_eq!(brief.field("families").unwrap().list().unwrap().len(), 1);
    assert_eq!(
        brief
            .field("deferredRelations")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        brief.field("counts").unwrap().field("counter").unwrap(),
        &Data::from(1usize)
    );
    assert_eq!(
        brief.field("presentationComplete").unwrap(),
        &Data::Bool(false)
    );
    assert!(clue_sexpr(brief).len() <= 8192);
    let reference = brief.field("deferredRelations").unwrap().list().unwrap()[0]
        .field("reference")
        .unwrap()
        .clone();
    let raw = owner
        .select(&[source], "query", &Data::List(vec![]), &limits, &cancel)
        .unwrap();
    assert_eq!(
        reference.field("contentIdentity").unwrap().text().unwrap(),
        raw.field("trace").unwrap().digest()
    );
    let mut expanded = request.map().unwrap().clone();
    expanded.insert(
        "checkpoint".into(),
        first.field("checkpoint").unwrap().clone(),
    );
    expanded.insert(
        "displayBytes".into(),
        (2 * clue_sexpr(&raw).len() + 8192).into(),
    );
    let second = owner
        .slice_selected(
            &[source],
            "query",
            &Data::Map(expanded.clone()),
            &limits,
            &cancel,
        )
        .unwrap();
    let expanded_brief = second.field("brief").unwrap();
    assert!(
        expanded_brief
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        expanded_brief
            .field("association")
            .unwrap()
            .field("trace")
            .unwrap(),
        raw.field("trace").unwrap()
    );
    assert_eq!(
        expanded_brief.field("presentationComplete").unwrap(),
        &Data::Bool(true)
    );
    expanded.insert(
        "checkpoint".into(),
        second.field("checkpoint").unwrap().clone(),
    );
    expanded.insert("displayBytes".into(), 8192usize.into());
    let repeated = owner
        .slice_selected(&[source], "query", &Data::Map(expanded), &limits, &cancel)
        .unwrap();
    let unchanged = repeated.field("brief").unwrap();
    assert!(
        unchanged
            .field("families")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        unchanged
            .field("retainedRelations")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        1
    );
    assert!(
        unchanged
            .field("deferredRelations")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    assert!(
        !unchanged
            .field("association")
            .unwrap()
            .map()
            .unwrap()
            .contains_key("trace")
    );
    assert_eq!(
        unchanged.field("counts").unwrap(),
        brief.field("counts").unwrap()
    );
}

#[test]
fn clues_observation_counter_and_unknown_are_distinct() {
    let engine = Engine::new(1).unwrap();
    let mut owner = exchange(&engine);
    let result = owner
        .read(
            &["old-is-unexplored".into(), "novel".into()],
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        result
            .field("counterevidence")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        1
    );
    assert!(result.field("support").unwrap().list().unwrap().is_empty());
    assert_eq!(result.field("unknown").unwrap(), &list(&[&["novel"]]));
    assert!(clue_sexpr(&result).contains("not-same-cause"));
}
#[test]
fn clues_source_mismatch_is_rejected() {
    let engine = Engine::new(1).unwrap();
    assert!(
        ClueExchange::new(
            &engine,
            &[PROJECTION],
            "project",
            &facts(),
            &Data::object([("receipt", "other".into())]),
            &Limits::default(),
            &Cancellation::default()
        )
        .is_err()
    );
}
#[test]
fn clues_novel_hypothesis_selects_without_promotion_or_closed_vocabulary() {
    let engine = Engine::new(1).unwrap();
    let mut owner = exchange(&engine);
    let hint = Data::object([
        ("id", "new".into()),
        ("claim", "novel".into()),
        ("polarity", "support".into()),
        ("source", "agent".into()),
        ("factors", list(&[&["unlisted-factor", "unlisted-value"]])),
    ]);
    owner.submit(&Data::List(vec![hint.clone()])).unwrap();
    let selected = owner
        .select(
            &[PROJECTION],
            "select",
            &list(&[&["unlisted-factor", "unlisted-value"]]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(selected.field("question").unwrap(), &list(&[&["novel"]]));
    let result = owner
        .read(
            &["novel".into()],
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(result.field("support").unwrap().list().unwrap().is_empty());
    assert_eq!(
        result.field("conditional").unwrap().list().unwrap().len(),
        1
    );
    assert_eq!(result.field("unknown").unwrap(), &list(&[&["novel"]]));
    assert!(owner.submit(&Data::List(vec![hint])).is_err());
}
#[test]
fn clues_failed_batch_does_not_partially_publish() {
    let engine = Engine::new(1).unwrap();
    let mut owner = exchange(&engine);
    let hint = Data::object([
        ("id", "new".into()),
        ("claim", "novel".into()),
        ("polarity", "support".into()),
        ("source", "agent".into()),
    ]);
    assert!(owner.submit(&Data::List(vec![hint.clone(), hint])).is_err());
    let result = owner
        .read(
            &["novel".into()],
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(
        result
            .field("conditional")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn clues_collision_cancellation_and_close_do_not_create_authority() {
    let engine = Engine::new(1).unwrap();
    let mut owner = exchange(&engine);
    assert!(owner.include(exchange(&engine)).is_err());
    let canceled = Cancellation::default();
    canceled.cancel();
    assert!(
        owner
            .read(&["old-is-unexplored".into()], &Limits::default(), &canceled)
            .is_err()
    );
    let result = owner
        .read(
            &["old-is-unexplored".into()],
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        result
            .field("counterevidence")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        1
    );
    owner.close();
    assert!(
        owner
            .read(
                &["novel".into()],
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );
    assert!(owner.inventory().is_err());
    assert!(owner.submit(&Data::List(vec![])).is_err());
}
