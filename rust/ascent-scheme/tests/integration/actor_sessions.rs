//! A resident Scheme Actor survives independent production ABI control scopes.
use crate::support::Engine;
use gerbil_ascent::{GraphItem, ObjectInput};

#[test]
fn resident_actor_keeps_cuts_across_module_calls_and_value_apply() {
    let engine = Engine::new(12).unwrap();
    engine
        .register_module(
            "resident-actor",
            r#"
(import (only-in :clan/poo/object .ref)
        :gerbil-ascent/program/func
        (only-in :gerbil-ascent/program/session
                 gerbil-ascent-session-run gerbil-ascent-session-append-source!
                 gerbil-ascent-session-replace-source!)
        :gerbil-ascent/program/actor-session)
(export make-resident)
(def (make-resident)
  (let* ((x (gerbil-ascent-variable 'x))
         (y (gerbil-ascent-variable 'y))
         (z (gerbil-ascent-variable 'z))
         (program
          (gerbil-ascent-program
           (list (gerbil-ascent-relation 'edge 2 '((0 1) (1 2)))
                 (gerbil-ascent-relation 'reach 2 []))
           (list
            (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x y)))
              (list (gerbil-ascent-atom 'edge (list x y))))
            (gerbil-ascent-rule (list (gerbil-ascent-atom 'reach (list x z)))
              (list (gerbil-ascent-atom 'reach (list x y))
                    (gerbil-ascent-atom 'edge (list y z))))) 8 16 24))
         (session (gerbil-ascent-open-actor-session program workers: 1))
         (expected '((0 1) (1 2) (0 2))))
    (lambda (operation)
      (unless (= (##current-vm-processor-count) 1) (error "multiple VM processors"))
      (cond
       ((equal? operation "run")
        (let (rows ((.ref (gerbil-ascent-session-run session) 'rows-of) 'reach))
          (unless (and (= (length rows) (length expected))
                       (andmap (lambda (row) (member row rows)) expected))
            (error "resident Actor differs from independent closure"))
          (length rows)))
       ((equal? operation "append")
        (gerbil-ascent-session-append-source! session 'edge '(2 3))
        (set! expected '((0 1) (1 2) (0 2) (2 3) (1 3) (0 3))) 6)
       ((equal? operation "replace")
        (gerbil-ascent-session-replace-source! session 'edge '((0 1) (1 2)))
        (set! expected '((0 1) (1 2) (0 2))) 3)
       ((equal? operation "close") (gerbil-ascent-session-close! session) 0)
       (else (error "unknown resident Actor operation"))))))
"#,
        )
        .unwrap();
    let module = engine.module("resident-actor").unwrap();
    // Creation's ABI authority expires here. Each apply must use its new
    // request authority, including cache hits and source-cut replacements.
    let resident = module.call("make-resident", &[], None).unwrap();
    for (operation, expected) in [
        ("run", "3"),
        ("append", "6"),
        ("run", "6"),
        ("run", "6"),
        ("replace", "3"),
        ("run", "3"),
        ("run", "3"),
        ("close", "0"),
    ] {
        let result = resident
            .apply(&[ObjectInput::Text(operation.into())])
            .unwrap();
        assert!(
            matches!(&result.graph().unwrap().root, GraphItem::Number(value) if value == expected)
        );
    }
    assert!(resident.apply(&[ObjectInput::Text("run".into())]).is_err());
    module.close();
    engine.shutdown();
}
