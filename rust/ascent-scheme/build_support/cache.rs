//! Share only compiler-owned, fingerprint-checked work; detach consumer archives.
use super::policy;
use gerbil_scheme_aot_build::{CargoDirectiveKind, NativeArchiveLinkReceipt};
use std::{
    fs::{self, File, OpenOptions},
    path::{Path, PathBuf},
    time::Instant,
};

pub struct Lease {
    _lock: File,
    pub graph: PathBuf,
    pub archive: PathBuf,
    pub wait_ns: u128,
}
impl Lease {
    pub fn acquire(out: &Path) -> Result<Self, String> {
        // Cargo: <target>/<profile>/build/<package-hash>/out. Cross-target
        // builds retain a different target root; profile/features do not split it.
        let base = out
            .ancestors()
            .nth(policy::CACHE_PARENT_LEVELS)
            .ok_or("invalid Cargo OUT_DIR")?
            .join(policy::CACHE_NAMESPACE);
        Self::at(&base)
    }
    pub fn at(base: &Path) -> Result<Self, String> {
        fs::create_dir_all(base).map_err(|e| e.to_string())?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(base.join("build.lock"))
            .map_err(|e| e.to_string())?;
        let started = Instant::now();
        lock.lock().map_err(|e| e.to_string())?;
        let graph = base.join("graph");
        let archive = base.join("archive");
        fs::create_dir_all(&graph).map_err(|e| e.to_string())?;
        Ok(Self {
            _lock: lock,
            graph,
            archive,
            wait_ns: started.elapsed().as_nanos(),
        })
    }
    pub fn publish(&self, out: &Path, receipt: &NativeArchiveLinkReceipt) -> Result<(), String> {
        let private = out.join("archive");
        fs::create_dir_all(&private).map_err(|e| e.to_string())?;
        let name = receipt
            .archive_file
            .file_name()
            .ok_or("missing archive filename")?;
        // Copy while holding the lease. Rustc never links a mutable shared archive.
        fs::copy(&receipt.archive_file, private.join(name)).map_err(|e| e.to_string())?;
        let shared_search = format!("native={}", self.archive.display());
        for directive in &receipt.cargo_directives {
            let value = if directive.value == shared_search {
                format!("native={}", private.display())
            } else {
                directive.value.clone()
            };
            match directive.kind {
                CargoDirectiveKind::RustcLinkSearch => println!("cargo:rustc-link-search={value}"),
                CargoDirectiveKind::RustcLinkLib => println!("cargo:rustc-link-lib={value}"),
            }
        }
        Ok(())
    }
}
