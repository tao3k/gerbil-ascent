//! Contend across processes, using the actual SDK-built archive as the payload.
use super::{cache, input};
use gerbil_scheme_aot_build::NativeArchiveLinkReceipt;
use std::{
    fs,
    path::Path,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

const CLIENTS: usize = 12;
const ROUNDS: usize = 8;
const LIMIT: Duration = Duration::from_mins(3);
const ROOT_ENV: &str = "ASCENT_ARCHIVE_TEST_ROOT";

struct Children(Vec<Child>);
impl Drop for Children {
    fn drop(&mut self) {
        for child in &mut self.0 {
            if !matches!(child.try_wait(), Ok(Some(_))) {
                let _ = child.kill();
            }
            let _ = child.wait();
        }
    }
}

fn wait_for(mut ready: impl FnMut() -> bool, started: Instant) {
    while !ready() {
        assert!(
            started.elapsed() < LIMIT,
            "archive contention exceeded 180s"
        );
        thread::sleep(Duration::from_millis(5));
    }
}

pub fn run() {
    if let Some(root) = std::env::var_os(ROOT_ENV) {
        worker(Path::new(&root));
        return;
    }
    let started = Instant::now();
    let out = Path::new(env!("OUT_DIR"));
    let source = out.join("archive/libascent_hybrid.a");
    let expected = input::snapshot(&source).expect("SDK archive must exist");
    let root = out.join(format!("archive-stress-{}", std::process::id()));
    fs::create_dir(&root).unwrap();
    fs::create_dir_all(root.join("shared/archive")).unwrap();
    fs::copy(&source, root.join("shared/archive/libascent_hybrid.a")).unwrap();
    fs::write(root.join("counter"), "0").unwrap();
    let mut children = Children(Vec::with_capacity(CLIENTS));
    for client in 0..CLIENTS {
        children.0.push(
            Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "concurrent_archive_publishers",
                    "--nocapture",
                ])
                .env(ROOT_ENV, &root)
                .env("ASCENT_ARCHIVE_TEST_CLIENT", client.to_string())
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::inherit())
                .spawn()
                .unwrap(),
        );
    }
    wait_for(
        || {
            for child in &mut children.0 {
                assert!(
                    child.try_wait().unwrap().is_none(),
                    "worker exited before barrier"
                );
            }
            (0..CLIENTS).all(|n| root.join(format!("ready-{n}")).exists())
        },
        started,
    );
    fs::write(root.join("start"), []).unwrap();
    wait_for(
        || {
            let mut finished = true;
            for child in &mut children.0 {
                match child.try_wait().unwrap() {
                    Some(status) => assert!(status.success(), "archive worker failed: {status}"),
                    None => finished = false,
                }
            }
            finished
        },
        started,
    );
    let count = fs::read_to_string(root.join("counter")).unwrap();
    assert_eq!(count.parse::<usize>().unwrap(), CLIENTS * ROUNDS);
    for client in 0..CLIENTS {
        let actual =
            input::snapshot(&root.join(format!("client-{client}/archive/libascent_hybrid.a")))
                .unwrap();
        assert_eq!(actual["sha256"], expected["sha256"]);
        assert_eq!(actual["bytes"], expected["bytes"]);
    }
    let receipt = serde_json::json!({
        "clients": CLIENTS, "rounds": ROUNDS, "publications": CLIENTS * ROUNDS,
        "bytes": expected["bytes"], "sha256": expected["sha256"],
        "elapsed_ns": started.elapsed().as_nanos(), "accepted": true,
    });
    fs::write(out.join("archive-stress-result.json"), receipt.to_string()).unwrap();
    fs::remove_dir_all(&root).unwrap();
}

fn worker(root: &Path) {
    let started = Instant::now();
    let client = std::env::var("ASCENT_ARCHIVE_TEST_CLIENT").unwrap();
    let private = root.join(format!("client-{client}"));
    let source = root.join("shared/archive/libascent_hybrid.a");
    let expected = input::snapshot(&source).unwrap();
    fs::write(root.join(format!("ready-{client}")), []).unwrap();
    wait_for(|| root.join("start").exists(), started);
    let mut wait_ns = 0;
    for _ in 0..ROUNDS {
        let lease = cache::Lease::at(&root.join("shared")).unwrap();
        wait_ns += lease.wait_ns;
        let marker = root.join("active");
        let active = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&marker)
            .expect("exclusive lease allowed overlapping publishers");
        let receipt = NativeArchiveLinkReceipt {
            archive_name: "ascent_hybrid".into(),
            archive_file: source.clone(),
            cargo_directives: Vec::new(),
        };
        lease.publish(&private, &receipt).unwrap();
        let counter = fs::read_to_string(root.join("counter")).unwrap();
        fs::write(
            root.join("counter"),
            (counter.parse::<usize>().unwrap() + 1).to_string(),
        )
        .unwrap();
        drop(active);
        fs::remove_file(marker).unwrap();
        drop(lease);
        // Hash private bytes outside the lease while other processes publish.
        let actual = input::snapshot(&private.join("archive/libascent_hybrid.a")).unwrap();
        assert_eq!(actual["sha256"], expected["sha256"]);
        assert!(started.elapsed() < LIMIT);
    }
    fs::write(root.join(format!("wait-ns-{client}")), wait_ns.to_string()).unwrap();
}
