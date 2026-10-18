//! Key-value storage for stremio-core: one JSON file per key in a host-chosen directory.

use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use stremio_core::runtime::EnvError;

static DIRECTORY: OnceLock<PathBuf> = OnceLock::new();

pub fn install(directory: PathBuf) -> Result<(), EnvError> {
    std::fs::create_dir_all(&directory)
        .map_err(|error| EnvError::StorageWriteError(format!("{}: {error}", directory.display())))?;
    tracing::info!(directory = %directory.display(), "storage directory ready");
    DIRECTORY
        .set(directory)
        .map_err(|_| EnvError::Other("storage directory already set".to_owned()))
}

fn path_for(key: &str) -> PathBuf {
    let directory = DIRECTORY.get().expect("storage is installed before the runtime starts");
    file_path(directory, key)
}

fn file_path(directory: &Path, key: &str) -> PathBuf {
    directory.join(format!("{key}.json"))
}

pub fn read(key: &str) -> Result<Option<String>, EnvError> {
    read_at(&path_for(key))
}

pub fn write(key: &str, value: Option<&str>) -> Result<(), EnvError> {
    write_at(&path_for(key), value)
}

fn read_at(path: &Path) -> Result<Option<String>, EnvError> {
    match std::fs::read_to_string(path) {
        Ok(contents) => Ok(Some(contents)),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
        Err(error) => Err(EnvError::StorageReadError(format!("{}: {error}", path.display()))),
    }
}

fn write_at(path: &Path, value: Option<&str>) -> Result<(), EnvError> {
    let result = match value {
        // Write-then-rename so a crash never leaves a half-written file behind.
        Some(contents) => {
            let temporary = path.with_extension("json.tmp");
            std::fs::write(&temporary, contents).and_then(|_| std::fs::rename(&temporary, path))
        }
        None => match std::fs::remove_file(path) {
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            other => other,
        },
    };
    result.map_err(|error| EnvError::StorageWriteError(format!("{}: {error}", path.display())))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values_round_trip_and_removal_reads_as_missing() {
        let directory = tempfile::tempdir().unwrap();
        let path = file_path(directory.path(), "profile");

        assert_eq!(read_at(&path).unwrap(), None);
        write_at(&path, Some(r#"{"auth":null}"#)).unwrap();
        assert_eq!(read_at(&path).unwrap().as_deref(), Some(r#"{"auth":null}"#));
        write_at(&path, None).unwrap();
        assert_eq!(read_at(&path).unwrap(), None);
        write_at(&path, None).unwrap();
    }
}
