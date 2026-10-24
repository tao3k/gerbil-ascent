//! Installed resources retain source ownership and reject changed bytes before VM entry.
#![cfg(target_os = "macos")]
use ascent_scheme::InstancePool;
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
                Data::from("(defrules answer-form () ((_) (+ 40 2))) (def (answer) (answer-form))"),
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
