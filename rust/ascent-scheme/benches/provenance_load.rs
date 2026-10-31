//! Diagnostic load only: original mean/provenance semantics at twelve resident VMs.
use ascent_scheme::{Engine, Module, ModuleValue, RuleSession, SchemeProvenance};
use gerbil_ascent::{
    Cancellation, Error, FactLimits, Limits, ObjectInput, ProvenanceLimits, ProvenanceStatus,
    Result,
};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
    process::{Child, Command},
    sync::{Arc, Barrier},
    time::{Duration, Instant},
};

#[path = "support/owners.rs"]
mod owners;
use owners::Pool;
const CLIENTS: usize = 12;
const ROUNDS: usize = 16;
const FIXTURE: &str = include_str!("../../../t/qualification/evidence-api-module.ss");
type KeepAlive = (Engine, Module, ModuleValue);

fn numbers() -> ObjectInput {
    ObjectInput::List(
        [1, 2, 4]
            .into_iter()
            .map(|n| ObjectInput::Integer(n.into()))
            .collect(),
    )
}
fn sessions(pool: &Pool) -> Result<(Vec<RuleSession>, Vec<KeepAlive>)> {
    let engine = Engine::new(CLIENTS)?;
    if engine.threads() != CLIENTS {
        return Err(Error::Evaluation(
            "twelve Rust pool workers required".into(),
        ));
    }
    engine.register_module(":consumer/aggregate", FIXTURE)?;
    let mut sessions = Vec::new();
    let mut retained = Vec::new();
    for index in 0..CLIENTS {
        let engine = pool.bind(engine.clone(), index);
        let module = engine.module(":consumer/aggregate")?;
        let constructor = module.call("make-aggregate", &[numbers()], None)?;
        let session = constructor.open_session(FactLimits::default())?;
        module.close();
        sessions.push(session);
        retained.push((engine, module, constructor));
    }
    Ok((sessions, retained))
}
fn proof(
    session: &RuleSession,
    empty: bool,
    cancellation: &Cancellation,
) -> Result<SchemeProvenance> {
    let receipt = session.run(None, &Limits::default(), cancellation)?;
    let handle =
        u64::try_from(receipt.field("resultHandle")?.index()?).map_err(|_| Error::Closed)?;
    let lease = session.result(handle)?;
    if receipt.field("relations")?.field("average")?.list()?.len() != usize::from(!empty) {
        return Err(Error::Evaluation("mean row count changed".into()));
    }
    let limits = ProvenanceLimits::default();
    let evidence = session.provenance(handle, "average", &limits, cancellation)?;
    let graph = evidence.graph()?;
    if empty && graph.status != ProvenanceStatus::ClosedAbsent {
        return Err(Error::Evaluation(
            "empty mean proof is not closed absent".into(),
        ));
    }
    if !evidence.verify(&graph, &limits, cancellation)? {
        return Err(Error::Evaluation(
            "independent mean proof verification failed".into(),
        ));
    }
    lease.close();
    Ok(evidence)
}
fn exercise(session: &RuleSession) -> Result<()> {
    let cancellation = Cancellation::default();
    let limits = Limits::default();
    for round in 0..ROUNDS {
        if round != 0 {
            session.replace(
                BTreeMap::from([(
                    "number".into(),
                    vec![
                        vec![ObjectInput::Integer(1.into())],
                        vec![ObjectInput::Integer(2.into())],
                        vec![ObjectInput::Integer(4.into())],
                    ],
                )]),
                &limits,
                &cancellation,
            )?;
        }
        let evidence = proof(session, false, &cancellation)?;
        session.replace(
            BTreeMap::from([("number".into(), vec![])]),
            &limits,
            &cancellation,
        )?;
        if !matches!(evidence.graph(), Err(Error::Closed)) {
            return Err(Error::Evaluation(
                "source replacement retained stale proof authority".into(),
            ));
        }
        proof(session, true, &cancellation)?;
    }
    Ok(())
}
fn archive_ready(child: &mut Child) -> bool {
    let marker = Path::new(env!("OUT_DIR")).join(format!("archive-stress-{}/start", child.id()));
    let started = Instant::now();
    while started.elapsed() < Duration::from_mins(3) {
        if marker.exists() {
            return matches!(child.try_wait(), Ok(None));
        }
        if !matches!(child.try_wait(), Ok(None)) {
            return false;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    false
}
fn run_clients(sessions: Vec<RuleSession>, archive_test: &Path) -> Result<bool> {
    let ready = Arc::new(Barrier::new(CLIENTS + 1));
    let start = Arc::new(Barrier::new(CLIENTS + 1));
    std::thread::scope(|scope| {
        let mut handles = Vec::new();
        for (index, session) in sessions.into_iter().enumerate() {
            let ready = ready.clone();
            let start = start.clone();
            handles.push(scope.spawn(move || {
                ready.wait();
                start.wait();
                let result = exercise(&session);
                match &result {
                    Ok(()) => {
                        eprintln!("PROVENANCE-LOAD client={index} rounds={ROUNDS} status=success");
                    }
                    Err(error) => {
                        eprintln!("PROVENANCE-LOAD client={index} status=failed error={error}");
                    }
                }
                result
            }));
        }
        ready.wait();
        let mut archive = Command::new(archive_test)
            .args(["--exact", "concurrent_archive_publishers", "--nocapture"])
            .spawn();
        let overlap = archive.as_mut().is_ok_and(archive_ready);
        eprintln!(
            "PROVENANCE-LOAD-START vms={CLIENTS} processors_per_vm=1 rust_threads={CLIENTS} rounds={ROUNDS} archive_overlap_at_release={overlap} diagnostic_only=true"
        );
        start.wait();
        let mut complete = overlap;
        for handle in handles {
            match handle.join() {
                Ok(Ok(())) => (),
                Ok(Err(_)) | Err(_) => complete = false,
            }
        }
        if let Ok(child) = &mut archive {
            complete &= child.wait().is_ok_and(|status| status.success());
        }
        Ok(complete)
    })
}
fn main() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if !(2..=3).contains(&args.len()) {
        return Err(Error::InvalidProgram(
            "expected worker, archive-test executables and optional vm|instances mode".into(),
        ));
    }
    let mode = args.get(2).map_or("vm", String::as_str);
    if mode != "vm" && mode != "instances" {
        return Err(Error::InvalidProgram("unknown VM owner mode".into()));
    }
    let pool = Pool::start(mode, CLIENTS, &args[0]);
    let receipts = pool.receipts();
    if receipts.len() != CLIENTS || receipts.iter().any(|receipt| receipt.processors != 1) {
        return Err(Error::Evaluation(
            "twelve single-processor VM owners required".into(),
        ));
    }
    let pids: BTreeSet<_> = receipts.iter().map(|receipt| receipt.pid).collect();
    let domains: BTreeSet<_> = receipts.iter().map(|receipt| receipt.domain).collect();
    if pids.len() != (if mode == "instances" { 1 } else { CLIENTS }) || domains.len() != CLIENTS {
        return Err(Error::Evaluation(
            "owner mode requires exact process and VM domain identities".into(),
        ));
    }
    for (client, receipt) in receipts.iter().enumerate() {
        eprintln!(
            "PROVENANCE-OWNER mode={mode} client={client} pid={} domain={} processors=1",
            receipt.pid, receipt.domain
        );
    }
    let (sessions, retained) = sessions(&pool)?;
    let complete = run_clients(sessions, Path::new(&args[1]))?;
    for (engine, module, value) in retained {
        value.close();
        module.close();
        engine.shutdown();
    }
    pool.finish();
    if !complete {
        return Err(Error::Evaluation(
            "provenance load diagnostic failed; no retries".into(),
        ));
    }
    eprintln!(
        "PROVENANCE-LOAD-COMPLETE mode={mode} proofs={} archive_overlap=true diagnostic_only=true",
        CLIENTS * ROUNDS * 2
    );
    Ok(())
}
