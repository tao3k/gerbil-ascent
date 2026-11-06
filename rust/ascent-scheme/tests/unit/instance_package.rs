//! An inherited artifact lease must not remove a parent's captured files.
use super::InstancePackage;

#[test]
fn forked_package_drop_preserves_the_parent_resource_owner() {
    let package = InstancePackage::bundled().unwrap();
    let path = package.resources().unwrap().path().to_owned();
    // Keep the manifest allocated in the child: its branch performs only
    // getpid, reference-count decrements and _exit after fork.
    let manifest = package.manifest.clone();
    // SAFETY: the child neither enters a VM nor allocates after fork. The
    // process-local package drop forgets the inherited file-owner reference.
    let child = unsafe { libc::fork() };
    assert!(child >= 0);
    if child == 0 {
        drop(package);
        // SAFETY: no inherited thread/runtime destructor executes in the child.
        unsafe { libc::_exit(0) }
    }
    let mut status = 0;
    // SAFETY: child is this test's owned process; status is a live stack word.
    assert_eq!(unsafe { libc::waitpid(child, &raw mut status, 0) }, child);
    assert_eq!(status, 0);
    assert!(path.is_dir(), "child drop removed the parent's package");
    package.verify().unwrap();
    drop(manifest);
    drop(package);
    assert!(
        !path.exists(),
        "the parent remains the resource retirement owner"
    );
}
