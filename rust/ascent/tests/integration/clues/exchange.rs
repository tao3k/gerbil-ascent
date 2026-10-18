use gerbil_ascent::{Cancellation, ClueExchange, Data, Engine, Limits, clue_sexpr};

pub(super) const PROJECTION: &str = r"
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
";

pub(super) fn list(rows: &[&[&str]]) -> Data {
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
        let brief = at(&result, &["brief"]);
        assert!(clue_sexpr(brief).len() <= 8192);
        grouped |= brief.map().unwrap().contains_key("deferredScope");
        let page = rows(brief, &["families"]);
        for family in page {
            assert!(seen.insert(at(family, &["claim"]).text().unwrap().to_owned()));
            assert_eq!(rows(family, &["observations"]).len(), 2);
        }
        if at(brief, &["presentationComplete"]) == &Data::Bool(true) {
            complete = true;
            break;
        }
        assert!(
            !page.is_empty(),
            "a complete family fits but the read made no progress"
        );
        request.insert("checkpoint".into(), at(&result, &["checkpoint"]).clone());
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
    let source = r"(define-evidence (shared-select)
      (sources clue factor binding) (outputs question)
      (include clue-selection-schema)
      (relation question (claim))
      ((question C) <-- (clue I D C _ _ _) (factor I D N V) (binding N V)))";
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

pub(super) fn anchored_exchange(engine: &Engine, condition: &str) -> ClueExchange {
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
    let support = rows(&result, &["support"]);
    let counter = rows(&result, &["counterevidence"]);
    assert_eq!(support.len(), 1);
    assert_eq!(counter.len(), 1);
    assert_eq!(support[0].list().unwrap()[0], Data::from("header"));
    assert_eq!(counter[0].list().unwrap()[0], Data::from("header"));
    assert_eq!(support[0].list().unwrap()[3], Data::from("trace-a"));
    assert_eq!(counter[0].list().unwrap()[3], Data::from("trace-b"));
    assert!(!support[0].list().unwrap()[4].text().unwrap().is_empty());
    assert!(!counter[0].list().unwrap()[4].text().unwrap().is_empty());
    assert_eq!(at(&result, &["conflict"]), &list(&[&["header"]]));
    assert_eq!(rows(&result, &["neighbor"]).len(), 1);
    assert_eq!(at(&result, &["unknown"]), &list(&[]));
    assert_eq!(at(&result, &["selection", "association_gap"]), &list(&[]));
    assert_eq!(at(&result, &["selection", "applicability_gap"]), &list(&[]));
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
        assert_eq!(at(&result, &["selection"]).field(gap).unwrap(), &expected);
        assert_eq!(at(&result, &["support"]), &list(&[]));
        assert_eq!(at(&result, &["counterevidence"]), &list(&[]));
        assert_eq!(at(&result, &["unknown"]), &list(&[]));
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
    let brief = at(&first, &["brief"]);
    assert_eq!(at(brief, &["counts", "support"]), &Data::from(1usize));
    assert_eq!(at(brief, &["counts", "counter"]), &Data::from(1usize));
    assert_eq!(rows(brief, &["families"]).len(), 1);
    assert_eq!(
        rows(brief, &["families"])[0]
            .field("observations")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        2
    );
    let mut repeated = request.map().unwrap().clone();
    repeated.insert("checkpoint".into(), at(&first, &["checkpoint"]).clone());
    let unchanged = owner
        .slice_selected(
            &[ANCHORED_SELECTOR],
            "anchored",
            &Data::Map(repeated.clone()),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(rows(&unchanged, &["brief", "families"]).is_empty());
    assert_eq!(
        at(&unchanged, &["brief", "delta", "added"]),
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
        at(&collapsed, &["brief", "presentationComplete"]),
        &Data::Bool(false)
    );
    assert_eq!(
        at(&collapsed, &["checkpoint", "body", "items"]),
        &Data::List(vec![])
    );
    let summary = &rows(&collapsed, &["brief", "deferred"])[0];
    assert_eq!(at(summary, &["counts", "counter"]), &Data::from(1usize));
    assert!(clue_sexpr(at(&collapsed, &["brief"])).len() <= capacity);
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
    assert_eq!(at(&expanded, &["brief", "mode"]), &Data::from("rescope"));
    assert_eq!(rows(&expanded, &["brief", "families"]).len(), 2);
    let mut invalid = request.map().unwrap().clone();
    invalid.insert(
        "checkpoint".into(),
        Data::object([
            ("body", at(&first, &["checkpoint", "body"]).clone()),
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
        (clue_sexpr(at(&full, &["brief"])).len() - 1).into(),
    );
    let first = owner
        .slice(&Data::Map(paged.clone()), &limits, &cancel)
        .unwrap();
    let brief = at(&first, &["brief"]);
    let shown = rows(brief, &["families"]);
    assert_eq!(shown.len(), 1);
    assert_eq!(rows(brief, &["deferred"]).len(), 1);
    assert_eq!(at(brief, &["presentationComplete"]), &Data::Bool(false));
    let first_claim = shown[0].field("claim").unwrap().clone();
    let checkpoint = at(&first, &["checkpoint"]).clone();
    assert!(!rows(&checkpoint, &["body", "items"]).is_empty());
    paged.insert("checkpoint".into(), checkpoint);
    let second = owner.slice(&Data::Map(paged), &limits, &cancel).unwrap();
    let second_brief = at(&second, &["brief"]);
    let newly_shown = rows(second_brief, &["families"]);
    assert_eq!(newly_shown.len(), 1);
    assert_ne!(newly_shown[0].field("claim").unwrap(), &first_claim);
    assert_eq!(
        at(second_brief, &["presentationComplete"]),
        &Data::Bool(true)
    );
    let mut shrink = Data::object([("questions", Data::List(vec![first_claim]))])
        .map()
        .unwrap()
        .clone();
    shrink.insert("checkpoint".into(), at(&second, &["checkpoint"]).clone());
    let smaller = owner.slice(&Data::Map(shrink), &limits, &cancel).unwrap();
    let smaller_brief = at(&smaller, &["brief"]);
    assert_eq!(at(smaller_brief, &["mode"]), &Data::from("rescope"));
    assert!(rows(smaller_brief, &["families"]).is_empty());
    assert_eq!(
        at(smaller_brief, &["delta", "removed"]),
        &Data::from(0usize)
    );
    let mut widen = all.map().unwrap().clone();
    widen.insert("checkpoint".into(), at(&smaller, &["checkpoint"]).clone());
    let repeated = owner
        .slice(&Data::Map(widen.clone()), &limits, &cancel)
        .unwrap();
    assert!(rows(&repeated, &["brief", "families"]).is_empty());
    // A source change still resets acknowledgement; history is not current evidence.
    let mut changed = anchored_exchange(&engine, "changed");
    let reset = changed.slice(&Data::Map(widen), &limits, &cancel).unwrap();
    assert_eq!(at(&reset, &["brief", "mode"]), &Data::from("reset"));
    assert_eq!(rows(&reset, &["brief", "families"]).len(), 2);
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
    let brief = at(&result, &["brief"]);
    assert_eq!(rows(brief, &["families"]).len(), 1);
    assert_eq!(rows(brief, &["association", "trace"]).len(), 1);
    assert_eq!(at(brief, &["counts", "counter"]), &Data::from(1usize));
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
    let source = r"(define-evidence (query)
      (sources clue factor attested) (outputs question trace)
      (include clue-selection-schema)
      (relation question (claim))
      (relation trace (claim left right))
      ((question C) <-- (clue I D C _ _ _) (attested I D _))
      ((trace C A B) <-- (clue I D C _ _ _) (attested I D _)
        (factor I D _ A) (factor I D _ B)))";
    let request = Data::object([("bindings", Data::List(vec![]))]);
    let first = owner
        .slice_selected(&[source], "query", &request, &limits, &cancel)
        .unwrap();
    let brief = at(&first, &["brief"]);
    assert_eq!(rows(brief, &["families"]).len(), 1);
    assert_eq!(rows(brief, &["deferredRelations"]).len(), 1);
    assert_eq!(at(brief, &["counts", "counter"]), &Data::from(1usize));
    assert_eq!(at(brief, &["presentationComplete"]), &Data::Bool(false));
    assert!(clue_sexpr(brief).len() <= 8192);
    let reference = rows(brief, &["deferredRelations"])[0]
        .field("reference")
        .unwrap()
        .clone();
    let raw = owner
        .select(&[source], "query", &Data::List(vec![]), &limits, &cancel)
        .unwrap();
    assert_eq!(
        at(&reference, &["contentIdentity"]).text().unwrap(),
        at(&raw, &["trace"]).digest()
    );
    let mut expanded = request.map().unwrap().clone();
    expanded.insert("checkpoint".into(), at(&first, &["checkpoint"]).clone());
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
    let expanded_brief = at(&second, &["brief"]);
    assert!(rows(expanded_brief, &["families"]).is_empty());
    assert_eq!(
        at(expanded_brief, &["association", "trace"]),
        at(&raw, &["trace"])
    );
    assert_eq!(
        at(expanded_brief, &["presentationComplete"]),
        &Data::Bool(true)
    );
    expanded.insert("checkpoint".into(), at(&second, &["checkpoint"]).clone());
    expanded.insert("displayBytes".into(), 8192usize.into());
    let repeated = owner
        .slice_selected(&[source], "query", &Data::Map(expanded), &limits, &cancel)
        .unwrap();
    let unchanged = at(&repeated, &["brief"]);
    assert!(rows(unchanged, &["families"]).is_empty());
    assert_eq!(rows(unchanged, &["retainedRelations"]).len(), 1);
    assert!(rows(unchanged, &["deferredRelations"]).is_empty());
    assert!(
        !at(unchanged, &["association"])
            .map()
            .unwrap()
            .contains_key("trace")
    );
    assert_eq!(at(unchanged, &["counts"]), at(brief, &["counts"]));
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
    assert_eq!(rows(&result, &["counterevidence"]).len(), 1);
    assert!(rows(&result, &["support"]).is_empty());
    assert_eq!(at(&result, &["unknown"]), &list(&[&["novel"]]));
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
    assert_eq!(at(&selected, &["question"]), &list(&[&["novel"]]));
    let result = owner
        .read(
            &["novel".into()],
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(rows(&result, &["support"]).is_empty());
    assert_eq!(rows(&result, &["conditional"]).len(), 1);
    assert_eq!(at(&result, &["unknown"]), &list(&[&["novel"]]));
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
    assert!(rows(&result, &["conditional"]).is_empty());
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
    assert_eq!(rows(&result, &["counterevidence"]).len(), 1);
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

pub(super) fn at<'a>(value: &'a Data, path: &[&str]) -> &'a Data {
    path.iter()
        .fold(value, |value, key| value.field(key).unwrap())
}

pub(super) fn rows<'a>(value: &'a Data, path: &[&str]) -> &'a [Data] {
    at(value, path).list().unwrap()
}
