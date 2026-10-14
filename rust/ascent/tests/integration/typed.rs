use gerbil_ascent::{Engine, GraphItem};
fn truth(source: &str) {
    let engine = Engine::new(2).unwrap();
    let owner = engine.load_definitions(source).unwrap();
    let value = owner.call("answer", &[], None).unwrap();
    assert!(matches!(
        value.graph().unwrap().root,
        GraphItem::Boolean(true)
    ));
}
#[test]
fn original_typed_nested_closures_normalize_to_native_recursive_rules() {
    truth(
        r"
      (def calls 0)
      (def (answer)
        (let* ((type (relational-relation-type 2 '(0 1 2)))
               (close (relational-typed-function type
                 (lambda (edge)
                   (set! calls (+ calls 1))
                   (relational-typed-fix (relational-typed-function type
                     (lambda (path)
                       (relational-typed-union edge
                         (relational-typed-project (relational-typed-join path edge 1 0) '(0 3)))))))))
               (input (relational-typed-source 'input type '((0 1) (1 2)))))
          (let-values (((program output)
             (relational-typed-compile (relational-typed-apply close input) +inf.0 +inf.0 +inf.0)))
            (let (rows (relational-query-name (relational-solve (relational-admit program)) output))
              (and (= calls 1) (= (length rows) 3)
                (andmap (lambda (row) (if (member row rows) #t #f)) '((0 1) (1 2) (0 2))))))))
    ",
    );
}
#[test]
fn finite_domain_order_does_not_change_structural_type_identity() {
    truth(
        r"
      (def (answer)
        (let ((a (relational-relation-type 1 '(0 1 1)))
              (b (relational-relation-type 1 '(1 0))))
          (and (relational-type=? a b)
            (equal? (relational-type-height-expression (relational-arrow-type a b))
                    '(* (expt 2 (expt 2 1)) (expt 2 1))))))
    ",
    );
}
#[test]
fn escaped_typed_parameters_and_insufficient_normalization_budget_are_rejected() {
    let engine = Engine::new(1).unwrap();
    let owner=engine.load_definitions(r"
      (def escaped #f)
      (def type (relational-relation-type 1 '(0 1)))
      (def fn (relational-typed-function type (lambda (x) (set! escaped x) x)))
      (def input (relational-typed-source 'input type '((0))))
      (def (escape) (relational-typed-compile escaped +inf.0 +inf.0 +inf.0))
      (def (small) (relational-typed-compile (relational-typed-apply fn input) +inf.0 +inf.0 +inf.0 1))
      (def (good) (relational-typed-compile (relational-typed-apply fn input) +inf.0 +inf.0 +inf.0))
    ").unwrap();
    assert!(owner.call("escape", &[], None).is_err());
    assert!(owner.call("small", &[], None).is_err());
    assert_eq!(
        owner
            .call("good", &[], None)
            .unwrap()
            .value_count()
            .unwrap(),
        2
    );
}

#[test]
fn function_fixed_points_use_full_finite_height_and_constant_bottom() {
    truth(
        r"
      (def type (relational-relation-type 1 '(0 1)))
      (def arrow (relational-arrow-type type type))
      (def input (relational-typed-source 'input type '((0))))
      (def fixed (relational-typed-fix (relational-typed-function arrow (lambda (prior) prior))))
      (def (answer)
        (let-values (((program output)
          (relational-typed-compile (relational-typed-apply fixed input) +inf.0 +inf.0 +inf.0)))
          (null? (relational-query-name (relational-solve (relational-admit program)) output))))
    ",
    );
}
#[test]
fn metadata_getters_cannot_mutate_frozen_typed_source_data() {
    truth(
        r"
      (def type (relational-relation-type 1 '(0 1)))
      (def source (relational-typed-source 'input type '((0))))
      (def (answer)
        (vector-set! (relational-typed-term-data source) 1 '((9)))
        (let-values (((program output) (relational-typed-compile source +inf.0 +inf.0 +inf.0)))
          (equal? (relational-query-name (relational-solve (relational-admit program)) output) '((0)))))
    ",
    );
}
