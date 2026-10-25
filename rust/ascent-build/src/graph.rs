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
pub fn prepare(
    root: &Path,
    prefix: &Path,
    shared: &Lease,
    observer: &Observer,
) -> Result<(), String> {
    let workspace = source_workspace();
    for source in [
        root.join("build.ss"),
        root.join("build-modules.ss"),
        workspace.join("build.ss"),
        workspace.join("scheme/program-build.ss"),
        workspace.join("scheme/program-metadata.ss"),
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
            .env("GERBIL_PATH", prefix),
    )?;
    // This consumer needs compiled library carriers and its AOT entry, not
    // the package's CLI/shared-library executable targets. std/make validates
    // the complete declared library inventory below on every configuration.
    // Keep one graph across macOS feature/profile combinations so enabling
    // instances does not invalidate an otherwise reusable archive. Linux keeps
    // the ordinary graph; its process owners use the SDK's existing carriers.
    let library_imports = if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        " '(:gerbil/compiler/base :gerbil-ascent/rules/interface :gerbil-ascent/rules/module)"
    } else {
        ""
    };
    let expression = format!(
        "(import :std/make {:?} {:?}) (make (map (lambda (module) (cons gxc: (cons module gerbil-ascent-compiler-options))) (append gerbil-ascent-library-modules [\"interface/hybrid\"])) srcdir: {:?} libdir: {:?} build-deps: {:?} optimize: #t) (gerbil-rs-stage-program {:?} {:?}{})",
        root.join("build-modules.ss")
            .to_str()
            .ok_or("non-UTF8 inventory path")?,
        workspace
            .join("scheme/program-build.ss")
            .to_str()
            .ok_or("non-UTF8 bridge path")?,
        root.to_str().ok_or("non-UTF8 root")?,
        prefix.join("lib").to_str().ok_or("non-UTF8 library path")?,
        shared
            .graph
            .join("build-deps")
            .to_str()
            .ok_or("non-UTF8 dependency path")?,
        root.join("interface/hybrid.ss")
            .to_str()
            .ok_or("non-UTF8 root")?,
        shared.graph.to_str().ok_or("non-UTF8 graph path")?,
        library_imports
    );
    process(
        observer,
        "graph-stage",
        gerbil_command("gxi")
            .args(["-:debug=q", "-e", &expression])
            .current_dir(root)
            .env("GERBIL_PATH", prefix),
    )
}
pub fn identify(
    root: &Path,
    prefix: &Path,
    out: &Path,
    gsc: &Path,
    observer: &Observer,
) -> Result<(), String> {
    process(
        observer,
        "source-identity",
        gerbil_command("gxi")
            .arg(root.join("interface/build-identity.ss"))
            .arg(root)
            .arg(out)
            .arg(prefix.join("lib"))
            .arg(
                gsc.parent()
                    .and_then(|p| p.parent())
                    .ok_or("invalid GSC path")?
                    .join("lib"),
            )
            .current_dir(root)
            .env("GERBIL_PATH", prefix),
    )
}
