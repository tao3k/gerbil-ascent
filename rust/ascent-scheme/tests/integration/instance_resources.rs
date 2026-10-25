//! Installed resources retain source ownership and reject changed bytes before VM entry.
#![cfg(target_os = "macos")]
use ascent_scheme::{InstancePackage, InstancePool};
use gerbil_ascent::Data;
use gerbil_scheme_python::PackageManifest;
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    time::Duration,
};
fn manifest() -> PackageManifest {
    PackageManifest::from_json(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/instance_inventory.json"
    )))
    .unwrap()
}
fn resource_directories() -> BTreeSet<PathBuf> {
    let prefix = format!("ascent-resources-{}-", std::process::id());
    fs::read_dir(std::env::temp_dir())
        .unwrap()
        .map(|entry| entry.unwrap())
        .filter(|entry| entry.file_name().to_string_lossy().starts_with(&prefix))
        .map(|entry| entry.path())
        .collect()
}
#[test]
fn resident_owner_uses_its_verified_resource_copy_after_package_removal() {
    let source = manifest()
        .verify(Path::new(env!("ASCENT_INSTANCE_PACKAGE")))
        .unwrap();
    let temporary = tempfile::tempdir().unwrap();
    source.copy_to(temporary.path()).unwrap();
    let before = resource_directories();
    let pool = InstancePool::from_package(1, temporary.path()).unwrap();
    let after = resource_directories();
    let directories: Vec<_> = after.difference(&before).cloned().collect();
    assert_eq!(
        directories.len(),
        1,
        "one private source resource lease per pool"
    );
    temporary.close().unwrap();
    let owner = pool.owner(0).unwrap();
    let module = owner
        .call(Data::object([
            ("operation", Data::from("dsl-open")),
            ("trusted", Data::Bool(true)),
            (
                "source",
                Data::from("(defrules answer-form () ((_) (+ 40 2))) (def (answer) (answer-form)) (def (empty-reexport) (load-module \"gerbil-ascent/rules/interface\") (load-module \"gerbil-ascent/rules/interface\") #t)"),
            ),
        ]))
        .unwrap();
    let result = owner
        .call(Data::object([
            ("operation", Data::from("module-call")),
            ("owner", module.field("owner").unwrap().clone()),
            ("export", Data::from("answer")),
            ("arguments", Data::List(vec![])),
        ]))
        .unwrap();
    assert_eq!(
        result
            .field("value")
            .unwrap()
            .field("root")
            .unwrap()
            .field("value")
            .unwrap(),
        &Data::from("42")
    );
    // Empty runtime reexports have no linked Gambit descriptor. Their first
    // load and cached reload must retain the ordinary SDK loader behavior.
    let empty = owner
        .call(Data::object([
            ("operation", Data::from("module-call")),
            ("owner", module.field("owner").unwrap().clone()),
            ("export", Data::from("empty-reexport")),
            ("arguments", Data::List(vec![])),
        ]))
        .unwrap();
    assert_eq!(
        empty
            .field("value")
            .unwrap()
            .field("root")
            .unwrap()
            .field("value")
            .unwrap(),
        &Data::Bool(true)
    );
    let receipt = pool.shutdown(Duration::from_secs(30)).unwrap();
    assert_eq!(receipt.joined, 1);
    assert_eq!(receipt.pending, 0);
    assert_eq!(receipt.panicked, 0);
    assert!(
        directories.iter().all(|path| !path.exists()),
        "source files must retire before clean join publication"
    );
    assert!(
        receipt
            .owners
            .iter()
            .all(|owner| owner.status == 0 && owner.roots_before_cleanup == 0)
    );
    shared_snapshot_reverifies_and_retains_resources();
}
fn shared_snapshot_reverifies_and_retains_resources() {
    let source = manifest()
        .verify(Path::new(env!("ASCENT_INSTANCE_PACKAGE")))
        .unwrap();
    let temporary = tempfile::tempdir().unwrap();
    source.copy_to(temporary.path()).unwrap();
    let before = resource_directories();
    let package = InstancePackage::open(temporary.path()).unwrap();
    temporary.close().unwrap();
    let directories: Vec<_> = resource_directories()
        .difference(&before)
        .cloned()
        .collect();
    assert_eq!(directories.len(), 1, "one captured resource owner");
    let image = directories[0].join("_owners/ascent-instance.dylib");
    let original = fs::read(&image).unwrap();
    fs::write(&image, b"changed captured bytes").unwrap();
    let error = InstancePool::from_snapshot(1, &package)
        .err()
        .expect("fresh verification must reject edits");
    assert!(error.to_string().contains("resource identity mismatch"));
    fs::write(&image, original).unwrap();
    let first = InstancePool::from_snapshot(1, &package).unwrap();
    let second = InstancePool::from_snapshot(1, &package).unwrap();
    assert_ne!(first.receipts()[0].domain, second.receipts()[0].domain);
    assert_eq!(
        resource_directories().difference(&before).count(),
        1,
        "independent pools share only captured files"
    );
    let owner = second.owner(0).unwrap();
    assert_eq!(first.shutdown(Duration::from_secs(30)).unwrap().joined, 1);
    assert!(
        directories[0].is_dir(),
        "a caller and another VM still retain the files"
    );
    drop(package);
    owner
        .call(Data::object([
            ("operation", Data::from("dsl-open")),
            ("trusted", Data::Bool(true)),
            ("source", Data::from("(def (answer) (+ 40 2))")),
        ]))
        .unwrap();
    let receipt = second.shutdown(Duration::from_secs(30)).unwrap();
    assert_eq!(
        (receipt.joined, receipt.pending, receipt.panicked),
        (1, 0, 0)
    );
    assert!(
        receipt
            .owners
            .iter()
            .all(|owner| owner.status == 0 && owner.roots_before_cleanup == 0)
    );
    assert!(
        !directories[0].exists(),
        "last native join retires the captured files"
    );
}
#[test]
fn changed_package_image_is_rejected_by_the_compiled_manifest() {
    let source = manifest()
        .verify(Path::new(env!("ASCENT_INSTANCE_PACKAGE")))
        .unwrap();
    let temporary = tempfile::tempdir().unwrap();
    source.copy_to(temporary.path()).unwrap();
    fs::write(
        temporary.path().join("_owners/ascent-instance.dylib"),
        b"different image",
    )
    .unwrap();
    let error = InstancePool::from_package(1, temporary.path())
        .err()
        .expect("changed image must reject before loading");
    assert!(error.to_string().contains("resource identity mismatch"));
}
