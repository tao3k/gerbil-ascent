//! The same explicit owner population for production throughput and proof loads.
use ascent_scheme::{Engine, ProcessPool, WorkerProgram};
pub(crate) enum Pool {
    Process(ProcessPool),
    #[cfg(all(feature = "instances", target_os = "macos"))]
    Instances(ascent_scheme::InstancePool),
}
impl Pool {
    pub(crate) fn start(mode: &str, owners: usize, worker: &str) -> Self {
        if mode == "instances" {
            #[cfg(all(feature = "instances", target_os = "macos"))]
            return Self::Instances(ascent_scheme::InstancePool::new(owners).unwrap());
            #[cfg(not(all(feature = "instances", target_os = "macos")))]
            panic!("instances requires the qualified macOS instance image feature");
        }
        Self::Process(
            ProcessPool::with_program(owners, &WorkerProgram::new(worker, vec![])).unwrap(),
        )
    }
    pub(crate) fn finish(&self) {
        assert!(self.receipts().iter().all(|owner| owner.processors == 1));
        #[cfg(all(feature = "instances", target_os = "macos"))]
        if let Self::Instances(pool) = self {
            let receipt = pool.shutdown(std::time::Duration::from_secs(30)).unwrap();
            assert_eq!(receipt.joined, pool.receipts().len());
            assert_eq!(receipt.pending, 0);
            assert_eq!(receipt.panicked, 0);
            assert!(
                receipt
                    .owners
                    .iter()
                    .all(|owner| owner.status == 0 && owner.roots_before_cleanup == 0)
            );
            eprintln!(
                "OWNER-SHUTDOWN mode=instances joined={} pending=0 panicked=0 roots=0",
                receipt.joined
            );
        }
    }

    pub(crate) fn receipts(&self) -> Vec<ascent_scheme::ProcessReceipt> {
        match self {
            Self::Process(pool) => pool.receipts(),
            #[cfg(all(feature = "instances", target_os = "macos"))]
            Self::Instances(pool) => pool.receipts(),
        }
    }
    pub(crate) fn bind(&self, engine: Engine, index: usize) -> Engine {
        match self {
            Self::Process(pool) => engine.on_process(pool.owner(index).unwrap()),
            #[cfg(all(feature = "instances", target_os = "macos"))]
            Self::Instances(pool) => engine.on_instance(pool.owner(index).unwrap()),
        }
    }
}
