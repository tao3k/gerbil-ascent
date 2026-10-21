//! A quiescent native destructor is not an in-flight execution timeout.
use crate::service::{Worker, await_child};
use std::{
    process::Command,
    sync::{Arc, Mutex, mpsc},
    thread,
};
#[test]
fn drained_owner_waits_for_natural_cleanup_and_reaps_its_child() {
    let child = {
        // Release the fixture barrier after exec, before the three-second
        // retirement workload. Other test execution remains concurrent.
        let _setup = crate::process_wire::PROCESS_FIXTURE_SETUP.lock().unwrap();
        Command::new("sleep").arg("3").spawn().unwrap()
    };
    let pid = child.id();
    let child = Arc::new(Mutex::new(child));
    let watched = Arc::clone(&child);
    let (quiesced, drained) = mpsc::channel();
    let (finished, done) = mpsc::channel();
    let supervisor = thread::spawn(move || {
        quiesced.send(true).unwrap();
        await_child(&watched, pid, true);
        finished.send(()).unwrap();
    });
    drop(Worker {
        parent: std::process::id(),
        pid,
        sender: None,
        child: Arc::clone(&child),
        thread: Some(supervisor),
        drained,
        done,
    });
    assert!(child.lock().unwrap().try_wait().unwrap().unwrap().success());
}
