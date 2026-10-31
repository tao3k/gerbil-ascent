use super::{fs, io, transfer_with};
#[test]
fn link_failure_fallback_is_exact_and_permission_denial_preserves_artifacts() {
    let temp = tempfile::tempdir().unwrap();
    let source = temp.path().join("phase.o1");
    fs::write(&source, b"original").unwrap();
    for code in [1, 5, 13] {
        let target = temp.path().join(format!("denied-{code}")).join("phase.o1");
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        assert!(
            transfer_with(&source, &target, |_, _| Err(io::Error::from_raw_os_error(
                code
            )))
            .is_err()
        );
        assert!(!target.exists());
    }
    let target = temp.path().join("cross/phase.o1");
    fs::create_dir_all(target.parent().unwrap()).unwrap();
    assert_eq!(
        transfer_with(&source, &target, |_, _| Err(io::Error::new(
            io::ErrorKind::CrossesDevices,
            "cross volume"
        )))
        .unwrap(),
        "copied"
    );
    fs::write(&source, b"changed").unwrap();
    assert_eq!(fs::read(target).unwrap(), b"original");
}
