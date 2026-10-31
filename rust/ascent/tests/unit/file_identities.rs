//! Bulk hashing must preserve every original byte and path check.
use super::{file_identities, sha};
use std::{fs, path::PathBuf};

#[test]
fn full_hashes_match_serial_and_duplicate_paths_are_read_once() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().canonicalize().unwrap();
    let paths = (0..64)
        .map(|i| {
            let path = root.join(format!("source-{i}"));
            fs::write(&path, format!("source bytes {i}")).unwrap();
            path
        })
        .collect::<Vec<_>>();
    let expected = paths.iter().map(|p| (p.clone(), sha(p).unwrap())).collect();
    let mut repeated = paths.clone();
    repeated.extend(paths);
    assert_eq!(file_identities(&repeated).unwrap(), expected);
    assert!(file_identities(&[]).unwrap().is_empty());
}

#[test]
fn every_call_hashes_changed_bytes_and_missing_file_is_an_error() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().canonicalize().unwrap().join("source");
    fs::write(&path, "before").unwrap();
    let before = file_identities(std::slice::from_ref(&path)).unwrap();
    let times = fs::metadata(&path).unwrap().modified().unwrap();
    fs::write(&path, "after!").unwrap();
    fs::File::options()
        .write(true)
        .open(&path)
        .unwrap()
        .set_modified(times)
        .unwrap();
    let after = file_identities(std::slice::from_ref(&path)).unwrap();
    assert_ne!(before, after);
    fs::remove_file(&path).unwrap();
    assert!(file_identities(&[path]).is_err());
}

#[test]
fn aliases_directories_relative_and_traversal_paths_are_rejected() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().canonicalize().unwrap();
    let file = root.join("source");
    fs::write(&file, "bound bytes").unwrap();
    fs::create_dir(root.join("child")).unwrap();
    for path in [
        root.clone(),
        PathBuf::from("relative"),
        root.join("child/../source"),
    ] {
        assert!(file_identities(&[path]).is_err());
    }
    #[cfg(unix)]
    {
        let alias = root.join("alias");
        std::os::unix::fs::symlink(&file, &alias).unwrap();
        assert!(file_identities(&[alias]).is_err());
        let parent = root.join("parent-alias");
        std::os::unix::fs::symlink(root.join("child"), &parent).unwrap();
        fs::write(root.join("child/nested"), "nested").unwrap();
        assert!(file_identities(&[parent.join("nested")]).is_err());
    }
}
