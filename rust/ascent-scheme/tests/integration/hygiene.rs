use crate::support::Engine;
#[test]
fn dsl_macro_initializers_keep_definition_site_bindings() {
    let engine = Engine::new(1).unwrap();
    let module = engine
        .load_definitions(
            r"
        (def seed '((3)))
        (defrules scene () ((_ name)
          (ascent-fragment (relation name ((x exact-integer?)) seed))))
        (def (answer)
          (let (seed '((99)))
            (let (p (scene input))
              (equal? (.ref (car (.ref p 'relations)) 'rows) '((3))))))
    ",
        )
        .unwrap();
    assert!(matches!(
        module
            .call("answer", &[], None)
            .unwrap()
            .graph()
            .unwrap()
            .root,
        gerbil_ascent::GraphItem::Boolean(true)
    ));
}
