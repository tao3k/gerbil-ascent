use gerbil_ascent::{Cancellation, ClueExchange, Data, Engine, Limits, clue_sexpr};
use gerbil_ascent::{ClueProjection, ClueSelector};

#[test]
fn clues_projection_accepts_typed_observations_without_truthiness_coercion() {
    let source = "(define-evidence (project)
      (sources observed) (outputs clue factor link)
      (relation observed (flag count))
      (relation clue (id digest claim polarity role source))
      (relation factor (id digest name value))
      (relation link (claim target label id digest))
      ((clue (lit \"id\") (lit \"sha\") (lit \"claim\") (lit \"support\")
             (lit \"observation\") (lit \"receipt\")) <-- (observed (lit #f) (lit 1))))";
    let engine = Engine::new(std::thread::available_parallelism().unwrap().get()).unwrap();
    for (flag, expected) in [
        (Data::Bool(false), 1),
        (Data::from(0usize), 0),
        (Data::from("false"), 0),
    ] {
        let supplied = Data::object([(
            "observed",
            Data::List(vec![Data::List(vec![flag, Data::from(1usize)])]),
        )]);
        let mut owner = ClueExchange::new(
            &engine,
            ClueProjection {
                sources: &[source],
                constructor: "project",
                supplied: &supplied,
                attestations: &Data::object([("receipt", "sha".into())]),
            },
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
        assert_eq!(
            owner
                .inventory()
                .unwrap()
                .field("claims")
                .unwrap()
                .list()
                .unwrap()
                .len(),
            expected
        );
        owner.close();
    }
}

#[test]
fn clues_checkpoint_only_restores_declared_query_in_a_new_owner() {
    let engine = Engine::new(1).unwrap();
    let mut owner = exchange(&engine);
    let first = owner
        .slice_selected(
            ClueSelector {
                sources: &[PROJECTION],
                constructor: "select",
            },
            &Data::object([("bindings", list(&[&["mechanism", "old"]]))]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    owner.close();
    let request = Data::object([("checkpoint", at(&first, &["checkpoint"]).clone())]);
    let mut owner = exchange(&engine);
    let resumed = owner
        .slice(&request, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(at(&resumed, &["brief", "mode"]), &Data::from("incremental"));
    assert_eq!(rows(&resumed, &["brief", "families"]), []);
    assert_eq!(
        at(&resumed, &["brief", "delta", "added"]),
        &Data::from(0usize)
    );
    assert_eq!(
        at(&resumed, &["brief", "executionAuthorized"]),
        &Data::from(false)
    );

    let mut supplied = facts().map().unwrap().clone();
    let mut clues = supplied["clue"].list().unwrap().to_vec();
    clues.push(
        list(&[&[
            "added",
            "sha",
            "newly-discovered",
            "support",
            "observation",
            "receipt",
        ]])
        .list()
        .unwrap()[0]
            .clone(),
    );
    supplied.insert("clue".into(), Data::List(clues));
    supplied.insert(
        "factor".into(),
        list(&[
            &["known", "sha", "mechanism", "old"],
            &["added", "sha", "mechanism", "old"],
        ]),
    );
    let mut changed = ClueExchange::new(
        &engine,
        ClueProjection {
            sources: &[PROJECTION],
            constructor: "project",
            supplied: &Data::Map(supplied),
            attestations: &Data::object([("receipt", "sha".into())]),
        },
        &Limits::default(),
        &Cancellation::default(),
    )
    .unwrap();
    let refreshed = changed
        .slice(&request, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(at(&refreshed, &["brief", "mode"]), &Data::from("refresh"));
    assert_eq!(
        at(&refreshed, &["brief", "counts", "support"]),
        &Data::from(1usize)
    );
    assert_eq!(
        at(&refreshed, &["brief", "counts", "counter"]),
        &Data::from(1usize)
    );
    let claims = rows(&refreshed, &["brief", "families"])
        .iter()
        .map(|family| family.field("claim").unwrap().text().unwrap())
        .collect::<Vec<_>>();
    assert!(claims.contains(&"newly-discovered"));
}

#[test]
fn clues_checkpoint_query_is_overridable_and_its_digest_is_checked() {
    let engine = Engine::new(1).unwrap();
    let mut owner = exchange(&engine);
    let first = owner
        .slice_selected(
            ClueSelector {
                sources: &[PROJECTION],
                constructor: "select",
            },
            &Data::object([("bindings", list(&[&["mechanism", "old"]]))]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    let checkpoint = at(&first, &["checkpoint"]).clone();
    let explicit = owner
        .slice(
            &Data::object([
                ("checkpoint", checkpoint.clone()),
                (
                    "questions",
                    Data::List(vec!["outside-original-scope".into()]),
                ),
            ]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(at(&explicit, &["brief", "mode"]), &Data::from("rescope"));
    assert_eq!(
        rows(&explicit, &["brief", "families"])[0]
            .field("claim")
            .unwrap(),
        &Data::from("outside-original-scope")
    );
    let other = owner
        .slice(
            &Data::object([
                ("checkpoint", checkpoint.clone()),
                ("bindings", list(&[&["mechanism", "unseen"]])),
            ]),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(
        at(&other, &["brief", "counts", "counter"]),
        &Data::from(0usize)
    );

    let mut body = checkpoint.field("body").unwrap().map().unwrap().clone();
    body.insert(
        "query".into(),
        Data::object([("questions", Data::List(vec!["forged".into()]))]),
    );
    let forged = Data::object([
        ("body", Data::Map(body)),
        ("digest", checkpoint.field("digest").unwrap().clone()),
    ]);
    assert!(
        owner
            .slice(
                &Data::object([("checkpoint", forged)]),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );

    let mut body = checkpoint.field("body").unwrap().map().unwrap().clone();
    body.remove("query");
    let body = Data::Map(body);
    let incomplete = Data::object([("digest", body.digest().into()), ("body", body)]);
    assert!(
        owner
            .slice(
                &Data::object([("checkpoint", incomplete.clone())]),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_err()
    );
    assert!(
        owner
            .slice(
                &Data::object([
                    ("checkpoint", incomplete),
                    ("questions", Data::List(vec!["old-is-unexplored".into()]))
                ]),
                &Limits::default(),
                &Cancellation::default()
            )
            .is_ok()
    );
}

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
        ClueProjection {
            sources: &[PROJECTION],
            constructor: "project",
            supplied: &facts(),
            attestations: &Data::object([("receipt", "sha".into())]),
        },
        &Limits::default(),
        &Cancellation::default(),
    )
    .unwrap()
}

#[test]
fn clues_unrelated_updates_keep_reads_but_changed_contracts_do_not() {
    let engine = Engine::new(1).unwrap();
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let mut first = exchange(&engine);
    let read = first
        .slice(
            &Data::object([("questions", Data::List(vec!["old-is-unexplored".into()]))]),
            &limits,
            &cancel,
        )
        .unwrap();
    let checkpoint = at(&read, &["checkpoint"]).clone();
    let mut input = facts().map().unwrap().clone();
    let mut clues = input["clue"].list().unwrap().to_vec();
    clues.push(Data::List(vec![
        "elsewhere".into(),
        "sha".into(),
        "outside-scope".into(),
        "support".into(),
        "observation".into(),
        "receipt".into(),
    ]));
    input.insert("clue".into(), Data::List(clues));
    let mut updated = ClueExchange::new(
        &engine,
        ClueProjection {
            sources: &[PROJECTION],
            constructor: "project",
            supplied: &Data::Map(input),
            attestations: &Data::object([("receipt", "sha".into())]),
        },
        &limits,
        &cancel,
    )
    .unwrap();
    let request = Data::object([("checkpoint", checkpoint.clone())]);
    let refreshed = updated.slice(&request, &limits, &cancel).unwrap();
    assert_eq!(at(&refreshed, &["brief", "mode"]), &Data::from("refresh"));
    assert!(rows(&refreshed, &["brief", "families"]).is_empty());
    assert_eq!(
        at(&refreshed, &["brief", "delta", "added"]),
        &Data::from(0usize)
    );
    let changed_rules = format!("{PROJECTION}\n; different declaration identity\n");
    let mut changed = ClueExchange::new(
        &engine,
        ClueProjection {
            sources: &[&changed_rules],
            constructor: "project",
            supplied: &facts(),
            attestations: &Data::object([("receipt", "sha".into())]),
        },
        &limits,
        &cancel,
    )
    .unwrap();
    let reset = changed.slice(&request, &limits, &cancel).unwrap();
    assert_eq!(at(&reset, &["brief", "mode"]), &Data::from("reset"));
    assert!(!rows(&reset, &["brief", "families"]).is_empty());
    let mut legacy = checkpoint.map().unwrap().clone();
    let mut body = legacy["body"].map().unwrap().clone();
    body.remove("readContractIdentity");
    let body = Data::Map(body);
    legacy.insert("digest".into(), body.digest().into());
    legacy.insert("body".into(), body);
    let reset = updated
        .slice(
            &Data::object([("checkpoint", Data::Map(legacy))]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert_eq!(at(&reset, &["brief", "mode"]), &Data::from("reset"));
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
        ClueProjection {
            sources: &[PROJECTION],
            constructor: "project",
            supplied: &input,
            attestations: &Data::object([("receipt", "sha".into())]),
        },
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
        .select(
            ClueSelector {
                sources: &[PROJECTION],
                constructor: "select",
            },
            &bindings,
            &limits,
            &cancel,
        )
        .unwrap();
    let shared = owner
        .select(
            ClueSelector {
                sources: &[source],
                constructor: "shared-select",
            },
            &bindings,
            &limits,
            &cancel,
        )
        .unwrap();
    assert_eq!(shared, explicit);
    let invalid = source.replace(
        "(relation question (claim))",
        "(relation question (claim)) ((clue I D C P R S) <-- (clue I D C P R S))",
    );
    assert!(
        owner
            .select(
                ClueSelector {
                    sources: &[&invalid],
                    constructor: "shared-select"
                },
                &bindings,
                &limits,
                &cancel
            )
            .is_err()
    );
    assert_eq!(
        owner
            .select(
                ClueSelector {
                    sources: &[source],
                    constructor: "shared-select"
                },
                &bindings,
                &limits,
                &cancel
            )
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
        ClueProjection {
            sources: &[PROJECTION],
            constructor: "project",
            supplied: &input,
            attestations: &Data::object([
                ("trace-a", "a".into()),
                ("trace-b", "b".into()),
                ("trace-c", "c".into()),
            ]),
        },
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
            ClueSelector {
                sources: &[ANCHORED_SELECTOR],
                constructor: "anchored",
            },
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
    assert_ne!(support[0].list().unwrap()[4].text().unwrap(), "");
    assert_ne!(counter[0].list().unwrap()[4].text().unwrap(), "");
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
                ClueSelector {
                    sources: &[ANCHORED_SELECTOR],
                    constructor: "anchored",
                },
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
    let selector = ClueSelector {
        sources: &[ANCHORED_SELECTOR],
        constructor: "anchored",
    };
    let engine = Engine::new(1).unwrap();
    let mut owner = anchored_exchange(&engine, "current");
    let request = Data::object([("bindings", list(&[&["mechanism", "publication"]]))]);
    let first = owner
        .slice_selected(
            selector,
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
            selector,
            &Data::Map(repeated.clone()),
            &Limits::default(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(rows(&unchanged, &["brief", "families"]), []);
    assert_eq!(
        at(&unchanged, &["brief", "delta", "added"]),
        &Data::from(0usize)
    );
    let capacity = clue_sexpr(brief).len() - 1;
    let mut small = request.map().unwrap().clone();
    small.insert("displayBytes".into(), capacity.into());
    let collapsed = owner
        .slice_selected(
            selector,
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
            selector,
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
                selector,
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
    assert_ne!(rows(&checkpoint, &["body", "items"]), []);
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
    assert_eq!(rows(smaller_brief, &["families"]), []);
    assert_eq!(
        at(smaller_brief, &["delta", "removed"]),
        &Data::from(0usize)
    );
    let mut widen = all.map().unwrap().clone();
    widen.insert("checkpoint".into(), at(&smaller, &["checkpoint"]).clone());
    let repeated = owner
        .slice(&Data::Map(widen.clone()), &limits, &cancel)
        .unwrap();
    assert_eq!(rows(&repeated, &["brief", "families"]), []);
    // Changed evidence is rederived; unrelated fully displayed families stay read.
    let mut changed = anchored_exchange(&engine, "changed");
    let reset = changed.slice(&Data::Map(widen), &limits, &cancel).unwrap();
    assert_eq!(at(&reset, &["brief", "mode"]), &Data::from("refresh"));
    assert_eq!(rows(&reset, &["brief", "families"]).len(), 1);
    assert_eq!(
        at(&rows(&reset, &["brief", "families"])[0], &["claim"]),
        &Data::from("header")
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
            ClueSelector {
                sources: &[declaration],
                constructor: "query",
            },
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
        ClueProjection {
            sources: &[PROJECTION],
            constructor: "project",
            supplied: &Data::Map(supplied),
            attestations: &Data::object([("receipt", "sha".into())]),
        },
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
    let selector = ClueSelector {
        sources: &[source],
        constructor: "query",
    };
    let request = Data::object([("bindings", Data::List(vec![]))]);
    let first = owner
        .slice_selected(selector, &request, &limits, &cancel)
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
        .select(selector, &Data::List(vec![]), &limits, &cancel)
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
        .slice_selected(selector, &Data::Map(expanded.clone()), &limits, &cancel)
        .unwrap();
    let expanded_brief = at(&second, &["brief"]);
    assert_eq!(rows(expanded_brief, &["families"]), []);
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
        .slice_selected(selector, &Data::Map(expanded), &limits, &cancel)
        .unwrap();
    let unchanged = at(&repeated, &["brief"]);
    assert_eq!(rows(unchanged, &["families"]), []);
    assert_eq!(rows(unchanged, &["retainedRelations"]).len(), 1);
    assert_eq!(rows(unchanged, &["deferredRelations"]), []);
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
    assert_eq!(rows(&result, &["support"]), []);
    assert_eq!(at(&result, &["unknown"]), &list(&[&["novel"]]));
    assert!(clue_sexpr(&result).contains("not-same-cause"));
}
#[test]
fn clues_source_mismatch_is_rejected() {
    let engine = Engine::new(1).unwrap();
    assert!(
        ClueExchange::new(
            &engine,
            ClueProjection {
                sources: &[PROJECTION],
                constructor: "project",
                supplied: &facts(),
                attestations: &Data::object([("receipt", "other".into())])
            },
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
            ClueSelector {
                sources: &[PROJECTION],
                constructor: "select",
            },
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
    assert_eq!(rows(&result, &["support"]), []);
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
    assert_eq!(rows(&result, &["conditional"]), []);
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
