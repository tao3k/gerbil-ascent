//! Streaming source snapshots; copied bytes and compiler elapsed time are separate.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::Path,
};

pub fn snapshot(path: &Path) -> Result<Value, String> {
    read(path, None)
}

pub fn retain(path: &Path, contents: &Path) -> Result<Value, String> {
    let generated = matches!(
        path.extension().and_then(|s| s.to_str()),
        Some("scm" | "json")
    );
    read(path, generated.then_some(contents))
}

fn read(path: &Path, contents: Option<&Path>) -> Result<Value, String> {
    let mut file = File::open(path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let temporary = contents.map(|p| p.join(format!("snapshot-{}.tmp", std::process::id())));
    let mut retained = temporary
        .as_ref()
        .map(File::create)
        .transpose()
        .map_err(|e| e.to_string())?;
    let mut hash = Sha256::new();
    let mut bytes = 0_u64;
    let mut buffer = [0_u8; 16384];
    loop {
        let n = file.read(&mut buffer).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        hash.update(&buffer[..n]);
        if let Some(output) = &mut retained {
            output.write_all(&buffer[..n]).map_err(|e| e.to_string())?;
        }
        bytes = bytes.checked_add(n as u64).ok_or("source size overflow")?;
    }
    let digest = format!("{:x}", hash.finalize());
    drop(retained);
    if let (Some(directory), Some(temporary)) = (contents, temporary) {
        fs::rename(temporary, directory.join(&digest)).map_err(|e| e.to_string())?;
    }
    Ok(json!({"path": path, "bytes": bytes, "sha256": digest}))
}

/// Inputs written by this producer must not become Cargo inputs to itself.
/// Raw package sources are watched separately by the Scheme inventory owner.
pub fn externally_owned(source: &Path, generated: &Path, owned_static: &Path) -> bool {
    let owned_module = source.parent() == Some(owned_static)
        && source
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| {
                name.starts_with("gerbil-ascent__") || name.starts_with("gerbil-scheme-rust__")
            });
    !source.starts_with(generated) && !owned_module
}
