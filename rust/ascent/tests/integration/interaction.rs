use gerbil_ascent::{
    Data, DatalogRequest, Engine, EvidenceInteraction, EvidenceOperation, evaluate_datalog,
    read_datalog,
};
use std::collections::BTreeMap;
fn list(values: impl IntoIterator<Item = Data>) -> Data {
    Data::List(values.into_iter().collect())
}
fn graph() -> (Data, Data) {
    let facts = Data::object([("input", list([list(["a".into()]), list(["b".into()])]))]);
    let queries = Data::object([("answer", "out(X)".into())]);
    let graph = read_datalog(&DatalogRequest {
        facts: &facts,
        source: "out(X) <= input(X)",
        queries: &queries,
        schema: None,
    })
    .unwrap()
    .program;
    let sources = list(
        graph
            .field("relations")
            .unwrap()
            .list()
            .unwrap()
            .iter()
            .filter(|r| r.field("source").unwrap().boolean().unwrap())
            .cloned(),
    );
    (sources, graph)
}
fn tools(engine: &Engine) -> EvidenceInteraction {
    let (sources, graph) = graph();
    let operations = BTreeMap::from([
        (
            "closed".into(),
            EvidenceOperation::new(&graph, "out", "complete finite predicate", true).unwrap(),
        ),
        (
            "open".into(),
            EvidenceOperation::new(&graph, "out", "positive support only", false).unwrap(),
        ),
    ]);
    EvidenceInteraction::new(engine, sources, operations, true).unwrap()
}
fn condition(operation: &str, value: &str) -> Data {
    Data::object([
        ("operation", operation.into()),
        ("arguments", list([value.into()])),
    ])
}
fn branch(id: &str, conditions: Vec<Data>) -> Data {
    Data::object([("id", id.into()), ("conditions", list(conditions))])
}
fn first(packet: &Data) -> &Data {
    &packet.field("branches").unwrap().list().unwrap()[0]
}
#[test]
fn complete_false_conjunct_refutes_even_when_another_domain_is_open() {
    let engine = Engine::new(1).unwrap();
    let mut tools = tools(&engine);
    let result = tools
        .check(&list([branch(
            "candidate",
            vec![condition("closed", "missing"), condition("open", "unknown")],
        )]))
        .unwrap();
    let entry = first(&result.feedback);
    assert_eq!(entry.field("status").unwrap(), &Data::from("contradicted"));
    assert_eq!(entry.field("complete").unwrap(), &Data::Bool(true));
    assert_eq!(entry.field("domainComplete").unwrap(), &Data::Bool(false));
    assert_eq!(result.receipts.len(), 1);
    assert_eq!(
        result.feedback.field("taskCorrectnessCertified").unwrap(),
        &Data::Bool(false)
    );
}
#[test]
fn conjunction_order_is_irrelevant_but_owner_and_generation_are_required() {
    let engine = Engine::new(1).unwrap();
    let mut left = tools(&engine);
    let mut right = tools(&engine);
    let one = left
        .check(&list([branch(
            "one",
            vec![condition("closed", "a"), condition("closed", "b")],
        )]))
        .unwrap();
    let reference = first(&one.feedback).field("reference").unwrap().clone();
    let mut reordered = branch(
        "two",
        vec![condition("closed", "b"), condition("closed", "a")],
    )
    .map()
    .unwrap()
    .clone();
    reordered.insert("reference".into(), reference.clone());
    assert_eq!(
        first(
            &left
                .check(&list([Data::Map(reordered.clone())]))
                .unwrap()
                .feedback
        )
        .field("status")
        .unwrap(),
        &Data::from("supported")
    );
    assert_eq!(
        first(&right.check(&list([Data::Map(reordered)])).unwrap().feedback)
            .field("status")
            .unwrap(),
        &Data::from("unknown")
    );
    let (sources, _) = graph();
    left.replace(sources).unwrap();
    assert_eq!(
        first(&left.reuse(&list([reference])).unwrap().feedback)
            .field("status")
            .unwrap(),
        &Data::from("unknown")
    );
}
#[test]
fn candidate_batch_shares_one_complete_relation_evaluation() {
    let engine = Engine::new(2).unwrap();
    let mut tools = tools(&engine);
    let branches = list((0..128).map(|i| {
        branch(
            &i.to_string(),
            vec![condition(
                "closed",
                if i % 2 == 0 { "a" } else { "missing" },
            )],
        )
    }));
    for expected in [true, false] {
        let result = tools.check(&branches).unwrap();
        assert_eq!(result.receipts.len(), 1);
        assert_eq!(
            result.receipts[0].field("evaluated").unwrap(),
            &Data::Bool(expected)
        );
        let rows = result.feedback.field("branches").unwrap().list().unwrap();
        assert_eq!(
            rows.iter()
                .filter(|r| r.get("status") == Some(&Data::from("supported")))
                .count(),
            64
        );
    }
}
#[test]
fn native_datalog_types_preserve_boolean_integer_and_text_distinctions() {
    let engine = Engine::new(1).unwrap();
    let facts = Data::object([(
        "input",
        list([
            list([true.into()]),
            list([Data::Integer(1.into())]),
            list(["1".into()]),
        ]),
    )]);
    let queries = Data::object([("answer", "out(X)".into())]);
    let request = DatalogRequest {
        facts: &facts,
        source: "out(X) <= input(X)",
        queries: &queries,
        schema: None,
    };
    let (answer, _) = evaluate_datalog(&engine, &request).unwrap();
    assert_eq!(answer.field("answer").unwrap().list().unwrap().len(), 3);
    assert!(
        read_datalog(&DatalogRequest {
            schema: Some(&Data::from("infer")),
            ..request
        })
        .is_err()
    );
}

#[test]
fn journal_batch_rolls_back_receipts_when_checkpoint_is_invalid() {
    let engine = Engine::new(1).unwrap();
    let mut ledger = gerbil_ascent::Trajectory::new(&engine, "task", "source").unwrap();
    let before = ledger.snapshot().unwrap();
    let receipt = Data::object([
        ("id", "evidence".into()),
        ("kind", "evidence".into()),
        ("sourceIdentity", "source".into()),
        ("resultReference", "result".into()),
        ("pathIdentity", "path".into()),
    ]);
    let checkpoint = Data::object([
        ("id", "checkpoint".into()),
        ("kind", "checkpoint".into()),
        ("sourceIdentity", "source".into()),
        ("modelCall", "call:missing".into()),
        ("branches", list([])),
    ]);
    assert!(ledger.append_batch(&[receipt.clone(), checkpoint]).is_err());
    assert_eq!(ledger.snapshot().unwrap(), before);
    ledger.append(receipt).unwrap();
    assert_eq!(
        ledger.snapshot().unwrap().field("eventCount").unwrap(),
        &Data::from(1usize)
    );
}

#[test]
fn observed_set_equality_preserves_types_multiplicity_and_tuple_shape() {
    let one = list([list([Data::Integer(1.into())])]);
    assert!(
        gerbil_ascent::rows_equal(
            &one,
            &list([
                list([Data::Integer(1.into())]),
                list([Data::Integer(1.into())])
            ])
        )
        .unwrap()
    );
    assert!(!gerbil_ascent::rows_equal(&one, &list([list([true.into()])])).unwrap());
    assert!(!gerbil_ascent::rows_equal(&one, &list([list(["1".into()])])).unwrap());
    assert!(gerbil_ascent::rows_equal(&one, &list([list([]), list(["x".into()])])).is_err());
}

#[test]
fn restored_provider_history_keeps_opaque_items_and_rejects_duplicate_or_unpaired_tools() {
    use gerbil_ascent::{Data, ResponseHistory};
    let question = Data::object([
        ("role", Data::from("user")),
        ("content", Data::from("original")),
    ]);
    let call = Data::object([
        ("type", Data::from("function_call")),
        ("call_id", Data::from("one")),
        ("name", Data::from("check")),
        ("arguments", Data::from("{}")),
    ]);
    let result = Data::object([
        ("type", Data::from("function_call_output")),
        ("call_id", Data::from("one")),
        ("output", Data::from("finite facts")),
    ]);
    let reasoning = Data::object([
        ("type", Data::from("reasoning")),
        ("opaque", Data::from("unchanged")),
    ]);
    let input = Data::List(vec![
        question.clone(),
        reasoning,
        call.clone(),
        result.clone(),
    ]);
    let mut history = ResponseHistory::restore(&input).unwrap();
    assert_eq!(history.input().unwrap(), input);
    assert_eq!(history.reasoning_items(), 1);
    assert!(
        history
            .append_response(&Data::object([("output", Data::List(vec![call.clone()]))]))
            .is_err()
    );
    assert_eq!(history.input().unwrap(), input);
    assert!(ResponseHistory::restore(&Data::List(vec![question.clone(), call.clone()])).is_err());
    assert!(ResponseHistory::restore(&Data::List(vec![question.clone(), result.clone()])).is_err());
    assert!(
        ResponseHistory::restore(&Data::List(vec![question, call, result.clone(), result]))
            .is_err()
    );
}
