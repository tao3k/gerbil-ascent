//! Content-bound publication of producer-built artifacts. Never invokes a compiler.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs, io,
    path::{Component, Path, PathBuf},
};
use tempfile::TempDir;

type Result<T> = std::result::Result<T, ArtifactError>;
/// Filesystem failure or rejected producer identity.
#[derive(Debug)]
pub enum ArtifactError {
    Io(io::Error),
    Invalid(String),
}
impl From<io::Error> for ArtifactError {
    fn from(v: io::Error) -> Self {
        Self::Io(v)
    }
}
impl std::fmt::Display for ArtifactError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(e) => e.fmt(f),
            Self::Invalid(e) => e.fmt(f),
        }
    }
}
impl std::error::Error for ArtifactError {}
fn invalid(s: &str) -> ArtifactError {
    ArtifactError::Invalid(s.into())
}
fn text<'a>(v: &'a Value, k: &str) -> Result<&'a str> {
    v.get(k)
        .and_then(Value::as_str)
        .ok_or_else(|| invalid("invalid artifact receipt field"))
}
fn object<'a>(v: &'a Value, k: &str) -> Result<&'a serde_json::Map<String, Value>> {
    v.get(k)
        .and_then(Value::as_object)
        .ok_or_else(|| invalid("invalid artifact inventory"))
}
fn relative(path: &str, kind: &str) -> Result<PathBuf> {
    let path = Path::new(path);
    if path.as_os_str().is_empty()
        || path
            .components()
            .any(|p| !matches!(p, Component::Normal(_)))
    {
        return Err(invalid(kind));
    }
    Ok(path.into())
}
/// Hash actual file bytes and reject concurrent replacement or in-place changes.
/// # Errors
/// Reports unreadable files and identity changes during the read.
pub fn sha(path: &Path) -> Result<String> {
    let before = identity(path)?;
    let bytes = fs::read(path)?;
    if identity(path)? != before {
        return Err(invalid("artifact changed during validation"));
    }
    Ok(format!("{:x}", Sha256::digest(bytes)))
}
/// Hash canonical, deduplicated regular files in parallel, retaining each path.
/// Every invocation reads bytes again; no verification verdict is cached.
/// # Errors
/// Rejects relative paths, aliases, special files and changes during hashing.
#[cfg(feature = "rayon")]
pub fn file_identities(paths: &[PathBuf]) -> Result<BTreeMap<PathBuf, String>> {
    use rayon::iter::{IntoParallelRefIterator, ParallelIterator};
    let paths = paths.iter().collect::<std::collections::BTreeSet<_>>();
    let rows = paths
        .into_iter()
        .collect::<Vec<_>>()
        .par_iter()
        .map(|path| {
            if !path.is_absolute()
                || path
                    .components()
                    .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
                || fs::symlink_metadata(path)?.file_type().is_symlink()
                || !fs::metadata(path)?.is_file()
                || fs::canonicalize(path)? != **path
            {
                return Err(invalid("canonical regular identity path required"));
            }
            let hash = sha(path)?;
            if fs::canonicalize(path)? != **path {
                return Err(invalid("identity path changed during validation"));
            }
            Ok(((*path).clone(), hash))
        })
        .collect::<Vec<Result<_>>>();
    rows.into_iter().collect()
}

#[cfg(all(test, feature = "rayon"))]
#[path = "../tests/unit/file_identities.rs"]
mod identity_tests;
#[cfg(unix)]
fn identity(path: &Path) -> io::Result<(u64, u64, u64, i64, i64, i64, i64)> {
    use std::os::unix::fs::MetadataExt;
    let m = fs::metadata(path)?;
    Ok((
        m.dev(),
        m.ino(),
        m.len(),
        m.mtime(),
        m.mtime_nsec(),
        m.ctime(),
        m.ctime_nsec(),
    ))
}
#[cfg(not(unix))]
fn identity(
    path: &Path,
) -> io::Result<(
    u64,
    Option<std::time::SystemTime>,
    Option<std::time::SystemTime>,
)> {
    let m = fs::metadata(path)?;
    Ok((m.len(), m.modified().ok(), m.created().ok()))
}
fn generation(path: &Path) -> bool {
    path.extension().and_then(|s| s.to_str()).is_some_and(|s| {
        s.strip_prefix('o').is_some_and(|s| {
            !s.starts_with('0') && !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
        })
    })
}
fn transfer_with(
    source: &Path,
    target: &Path,
    link: impl FnOnce(&Path, &Path) -> io::Result<()>,
) -> Result<&'static str> {
    if generation(source) {
        if source.file_name() != target.file_name() {
            return Err(invalid("compiled generation filename changed"));
        }
        match link(&source.canonicalize()?, target) {
            Ok(()) => return Ok("linked-generation"),
            Err(e) => {
                // These are platform error kinds, not a broad copy-on-error policy.
                // EPERM, EACCES, EIO and unexpected errors always fail closed.
                let fallback = matches!(
                    e.kind(),
                    io::ErrorKind::CrossesDevices
                        | io::ErrorKind::Unsupported
                        | io::ErrorKind::TooManyLinks
                );
                if !fallback {
                    return Err(e.into());
                }
            }
        }
    }
    fs::copy(source, target)?;
    Ok("copied")
}
/// Transfer one immutable generation or copy a regular resource.
/// # Errors
/// Rejects renamed generations, denied links and filesystem failures.
pub fn transfer_resource(source: &Path, target: &Path) -> Result<&'static str> {
    transfer_with(source, target, |source, target| {
        fs::hard_link(source, target)
    })
}
fn verify_sources(root: &Path, receipt: &Value) -> Result<()> {
    for (name, digest) in object(receipt, "sourceInputs")? {
        let relative = relative(name, "invalid native source input path")?;
        let path = root.join(relative).canonicalize()?;
        if !path.starts_with(root) {
            return Err(invalid("invalid native source input path"));
        }
        if sha(&path)? != digest.as_str().unwrap_or("") {
            return Err(invalid("native build source identity changed"));
        }
    }
    Ok(())
}
fn stage_resources(receipt: &Value, build_dir: &Path, stage: &Path) -> Result<()> {
    for (name, asset) in object(receipt, "syntaxResources")? {
        let relative = relative(name, "invalid native resource path")?;
        let source = Path::new(text(asset, "path")?).canonicalize()?;
        if !source.starts_with(build_dir) {
            return Err(invalid("invalid native resource path"));
        }
        if sha(&source)? != text(asset, "sha256")? {
            return Err(invalid("native resource identity changed"));
        }
        let target = stage.join("syntax").join(relative);
        fs::create_dir_all(target.parent().unwrap())?;
        transfer_resource(&source, &target)?;
        if sha(&source)? != text(asset, "sha256")? || sha(&target)? != text(asset, "sha256")? {
            return Err(invalid("native resource changed during packaging"));
        }
    }
    Ok(())
}
fn admit_producer(root: &Path, library: &Path, sidecar: &Path) -> Result<Value> {
    if !library.is_file() || !sidecar.is_file() {
        return Err(invalid(
            "run gxi build.ss first; a successful native build receipt is required",
        ));
    }
    let receipt: Value = serde_json::from_slice(&fs::read(sidecar)?)
        .map_err(|_| invalid("invalid native build receipt"))?;
    if text(&receipt, "schema")? != "ascent.c-abi-build.v1"
        || text(&receipt, "buildOwner")? != "build.ss/std/make"
        || sha(library)? != text(&receipt, "librarySha256")?
    {
        return Err(invalid("native build receipt does not match its artifact"));
    }
    verify_sources(root, &receipt)?;
    Ok(receipt)
}
fn publication_target(output: &Path) -> Result<PathBuf> {
    let parent = output
        .parent()
        .ok_or_else(|| invalid("artifact output parent required"))?;
    fs::create_dir_all(parent)?;
    let output = parent.canonicalize()?.join(
        output
            .file_name()
            .ok_or_else(|| invalid("artifact output filename required"))?,
    );
    Ok(output)
}
/// A fully staged candidate. Publication rechecks all producer identities.
pub struct Publication {
    temporary: TempDir,
    root: PathBuf,
    output: PathBuf,
    library: PathBuf,
    sidecar: PathBuf,
    receipt: Value,
    receipt_sha: String,
}
impl Publication {
    /// Admit the producer and stage a content-checked candidate.
    /// # Errors
    /// Rejects missing or changed producer inputs and staging failures.
    pub fn prepare(root: &Path, output: &Path, build_dir: &Path) -> Result<Self> {
        let root = root.canonicalize()?;
        let build_dir = build_dir.canonicalize()?;
        let library = build_dir.join("bin/libascent");
        let sidecar = build_dir.join("bin/libascent.json");
        let receipt = admit_producer(&root, &library, &sidecar)?;
        let output = publication_target(output)?;
        let temporary = tempfile::Builder::new()
            .prefix(".ascent-package-")
            .tempdir_in(
                output
                    .parent()
                    .ok_or_else(|| invalid("artifact output parent required"))?,
            )?;
        fs::create_dir(temporary.path().join("syntax"))?;
        let receipt_sha = sha(&sidecar)?;
        stage_resources(&receipt, &build_dir, temporary.path())?;
        fs::copy(&library, temporary.path().join("library"))?;
        Ok(Self {
            temporary,
            root,
            output,
            library,
            sidecar,
            receipt,
            receipt_sha,
        })
    }
    /// Recheck staged bytes and atomically restore the previous cut on failure.
    /// # Errors
    /// Rejects changed staged inputs or reports publication and restoration failures.
    pub fn publish(mut self) -> Result<()> {
        verify_sources(&self.root, &self.receipt)?;
        let mut resources = serde_json::Map::new();
        let syntax = self
            .output
            .parent()
            .ok_or_else(|| invalid("artifact output parent required"))?
            .join("syntax");
        for (name, asset) in object(&self.receipt, "syntaxResources")? {
            if sha(Path::new(text(asset, "path")?))? != text(asset, "sha256")?
                || sha(&self.temporary.path().join("syntax").join(name))? != text(asset, "sha256")?
            {
                return Err(invalid("native resource changed before publication"));
            }
            resources.insert(
                name.clone(),
                json!({"path":syntax.join(name),"sha256":text(asset,"sha256")?}),
            );
        }
        if sha(&self.sidecar)? != self.receipt_sha
            || sha(&self.library)? != text(&self.receipt, "librarySha256")?
            || sha(&self.temporary.path().join("library"))? != text(&self.receipt, "librarySha256")?
        {
            return Err(invalid("native artifact changed during packaging"));
        }
        self.receipt["syntaxResources"] = Value::Object(resources);
        self.receipt["packagingOwner"] = json!("ascent.artifacts");
        self.receipt["nativeBuildReceiptSha256"] = json!(self.receipt_sha);
        let candidate_receipt = self.temporary.path().join("receipt");
        fs::write(
            &candidate_receipt,
            serde_json::to_vec_pretty(&self.receipt)
                .map_err(|_| invalid("artifact receipt serialization"))?,
        )?;
        let receipt_path = PathBuf::from(format!("{}.json", self.output.display()));
        // Keep all three previous artifacts until publication succeeds; failures
        // restore the complete previous cut, including its receipt.
        let targets = [syntax, self.output.clone(), receipt_path];
        let staged = [
            self.temporary.path().join("syntax"),
            self.temporary.path().join("library"),
            candidate_receipt,
        ];
        let mut backed = Vec::new();
        let mut published = Vec::new();
        let attempt = (|| -> io::Result<()> {
            for (i, target) in targets.iter().enumerate() {
                if target.exists() {
                    let backup = self.temporary.path().join(format!("previous-{i}"));
                    fs::rename(target, &backup)?;
                    backed.push((target.clone(), backup));
                }
            }
            for (source, target) in staged.iter().zip(&targets) {
                fs::rename(source, target)?;
                published.push(target.clone());
            }
            Ok(())
        })();
        if let Err(error) = attempt {
            for target in published.iter().rev() {
                if target.is_dir() {
                    fs::remove_dir_all(target)?;
                } else {
                    fs::remove_file(target)?;
                }
            }
            for (target, backup) in backed.iter().rev() {
                fs::rename(backup, target)?;
            }
            return Err(error.into());
        }
        Ok(())
    }
}
/// Publish artifacts already produced by the Scheme build.
/// # Errors
/// Preserves producer admission, staging and publication errors.
pub fn build(root: &Path, output: &Path, build_dir: &Path) -> Result<()> {
    Publication::prepare(root, output, build_dir)?.publish()
}
/// Validated on-disk artifact manifest, separate from execution data.
pub struct ArtifactReceipt(Value);
impl ArtifactReceipt {
    /// Convert the admitted manifest to the binding's typed value transport.
    /// # Errors
    /// Rejects unsupported manifest numeric encodings.
    pub fn into_data(self) -> Result<crate::Data> {
        manifest_data(self.0)
    }
}
fn manifest_data(value: Value) -> Result<crate::Data> {
    use crate::Data;
    Ok(match value {
        Value::Null => Data::Null,
        Value::Bool(v) => Data::Bool(v),
        Value::String(v) => Data::Text(v),
        Value::Number(v) => Data::Integer(
            v.to_string()
                .parse()
                .map_err(|_| invalid("artifact integer required"))?,
        ),
        Value::Array(v) => Data::List(v.into_iter().map(manifest_data).collect::<Result<_>>()?),
        Value::Object(v) => Data::Map(
            v.into_iter()
                .map(|(k, v)| Ok((k, manifest_data(v)?)))
                .collect::<Result<_>>()?,
        ),
    })
}
/// Content admission is immutable for each receipt path in one validator.
#[derive(Default)]
pub struct ArtifactValidation {
    receipts: BTreeMap<PathBuf, Value>,
}
impl ArtifactValidation {
    /// Whether this path has an admitted immutable identity.
    #[must_use]
    pub fn has_receipt(&self, path: &Path) -> bool {
        self.receipts.contains_key(path)
    }
    /// Validate actual producer bytes and bind this path to one immutable version.
    /// # Errors
    /// Rejects identity drift, path escapes and replacement of an admitted version.
    pub fn read(&mut self, library: &Path, path: &Path) -> Result<ArtifactReceipt> {
        self.validate_receipt(library, path).map(ArtifactReceipt)
    }
    fn validate_receipt(&mut self, library: &Path, path: &Path) -> Result<Value> {
        let before = identity(path)?;
        let receipt: Value = serde_json::from_slice(&fs::read(path)?)
            .map_err(|_| invalid("invalid artifact receipt"))?;
        let mut resources = serde_json::Map::new();
        if let Some(entries) = receipt.get("syntaxResources").and_then(Value::as_object) {
            for (name, asset) in entries {
                resources.insert(name.clone(), asset.get("sha256").unwrap_or(asset).clone());
            }
        }
        let version = json!({"library":receipt.get("librarySha256"),"extension":receipt.get("extensionSha256"),"resources":resources});
        if self.receipts.get(path).is_some_and(|v| *v != version) {
            return Err(invalid("artifact version changed; start a fresh process"));
        }
        if path.file_name().and_then(|v| v.to_str()) == Some("receipt.json") {
            let name = relative(text(&receipt, "library")?, "invalid native library path")?;
            if name.components().count() != 1 {
                return Err(invalid("invalid native library path"));
            }
            if sha(library)? != text(&receipt, "extensionSha256")?
                || sha(&path.parent().unwrap().join(name))? != text(&receipt, "librarySha256")?
            {
                return Err(invalid("native library identity drift"));
            }
        } else if sha(library)? != text(&receipt, "librarySha256")? {
            return Err(invalid("native library identity drift"));
        }
        for (name, expected) in resources {
            let name = relative(&name, "invalid native syntax resource path")?;
            let root = path.parent().unwrap().join("syntax").canonicalize()?;
            let resource = root.join(name).canonicalize()?;
            if !resource.starts_with(root) {
                return Err(invalid("invalid native syntax resource path"));
            }
            if sha(&resource)? != expected.as_str().unwrap_or("") {
                return Err(invalid("native syntax resource identity drift"));
            }
        }
        if identity(path)? != before {
            return Err(invalid("artifact receipt changed during validation"));
        }
        self.receipts.insert(path.into(), version);
        Ok(receipt)
    }
}

#[cfg(test)]
#[path = "../tests/unit/artifacts.rs"]
mod tests;
