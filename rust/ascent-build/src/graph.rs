//! Standard package admission and upstream compiler graph staging.
use super::{cache::Lease, observer::Observer};
use gerbil_scheme_aot_build::{
    ProgramArchiveObserver, ProgramArchiveOperation, gerbil_command,
    observe_program_archive_operation, run_native_process, source_workspace,
};
use std::{
    path::Path,
    process::{Command, Stdio},
};

pub fn process(
    observer: &Observer,
    phase: &'static str,
    command: &mut Command,
) -> Result<(), String> {
    command.stdin(Stdio::null());
    observe_program_archive_operation(
        observer,
        ProgramArchiveOperation {
            phase,
            operation: phase,
            subject: None,
        },
        || run_native_process(command, phase, true),
    )
}
pub fn prepare(root: &Path, shared: &Lease, observer: &Observer) -> Result<(), String> {
    let workspace = source_workspace();
    for source in [
        root.join("build.ss"),
        root.join("build-modules.ss"),
        workspace.join("build.ss"),
        workspace.join("scheme/program-build.ss"),
    ] {
        observer.observe_source_input(&source);
    }
    process(
        observer,
        "bridge-build",
        gerbil_command("gxi")
            .arg("-:debug=q")
            .arg(workspace.join("build.ss"))
            .arg("compile")
            .current_dir(&workspace)
            .env("GERBIL_PATH", root.join(".gerbil")),
    )?;
    // This consumer needs compiled library carriers and its AOT entry, not
    // the package's CLI/shared-library executable targets. std/make validates
    // the complete declared library inventory below on every configuration.
    let expression = format!(
        "(import :std/make (only-in :asp-gerbil-scheme/src/build-api/native-spec-support normalize-spec) {:?} {:?}) (make (map (lambda (module) (normalize-spec module gerbil-ascent-compiler-options)) (append gerbil-ascent-library-modules [\"interface/hybrid\"])) srcdir: {:?} libdir: {:?} build-deps: {:?} optimize: #t) (gerbil-rs-stage-program {:?} {:?})",
        root.join("build-modules.ss")
            .to_str()
            .ok_or("non-UTF8 inventory path")?,
        workspace
            .join("scheme/program-build.ss")
            .to_str()
            .ok_or("non-UTF8 bridge path")?,
        root.to_str().ok_or("non-UTF8 root")?,
        root.join(".gerbil/lib")
            .to_str()
            .ok_or("non-UTF8 library path")?,
        shared
            .graph
            .join("build-deps")
            .to_str()
            .ok_or("non-UTF8 dependency path")?,
        root.join("interface/hybrid.ss")
            .to_str()
            .ok_or("non-UTF8 root")?,
        shared.graph.to_str().ok_or("non-UTF8 graph path")?
    );
    process(
        observer,
        "graph-stage",
        gerbil_command("gxi")
            .args(["-:debug=q", "-e", &expression])
            .current_dir(root)
            .env("GERBIL_PATH", root.join(".gerbil")),
    )
}
pub fn identify(root: &Path, out: &Path, gsc: &Path, observer: &Observer) -> Result<(), String> {
    process(
        observer,
        "source-identity",
        gerbil_command("gxi")
            .arg(root.join("interface/build-identity.ss"))
            .arg(root)
            .arg(out)
            .arg(root.join(".gerbil/lib"))
            .arg(
                gsc.parent()
                    .and_then(|p| p.parent())
                    .ok_or("invalid GSC path")?
                    .join("lib"),
            )
            .current_dir(root),
    )
}
