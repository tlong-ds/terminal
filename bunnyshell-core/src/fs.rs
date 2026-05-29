use std::time::UNIX_EPOCH;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use crate::BunError;

use ignore::WalkBuilder;
use globset::{Glob, GlobSet, GlobSetBuilder};
use grep_regex::RegexMatcherBuilder;
use grep_searcher::sinks::UTF8;
use grep_searcher::{BinaryDetection, SearcherBuilder};
use ignore::WalkState;
use tempfile::NamedTempFile;

const MAX_READ_BYTES: u64 = 10 * 1024 * 1024; // 10 MB
const BINARY_SNIFF_BYTES: usize = 8 * 1024;
const FILE_SIZE_CAP: u64 = 5 * 1024 * 1024;
const DEFAULT_MAX_RESULTS: usize = 200;
const HARD_MAX_RESULTS: usize = 2000;
const MAX_SCANNED: usize = 50_000;

const PRUNE_DIRS: &[&str] = &[
    "node_modules",
    ".git",
    "target",
    "dist",
    "build",
    ".next",
    ".turbo",
    ".cache",
    ".venv",
    "__pycache__",
];

#[derive(uniffi::Enum)]
pub enum EntryKind {
    File,
    Dir,
    Symlink,
}

#[derive(uniffi::Record)]
pub struct DirEntry {
    pub name: String,
    pub kind: EntryKind,
    pub size: u64,
    pub mtime: u64,
}

#[derive(uniffi::Enum)]
pub enum ReadResult {
    Text { content: String, size: u64 },
    Binary { size: u64 },
    TooLarge { size: u64, limit: u64 },
}

#[derive(uniffi::Enum)]
pub enum StatKind {
    File,
    Dir,
    Symlink,
}

#[derive(uniffi::Record)]
pub struct FileStat {
    pub size: u64,
    pub mtime: u64,
    pub kind: StatKind,
}

#[derive(uniffi::Record)]
pub struct SearchHit {
    pub path: String,
    pub rel: String,
    pub name: String,
    pub is_dir: bool,
}

#[derive(uniffi::Record)]
pub struct SearchResult {
    pub hits: Vec<SearchHit>,
    pub truncated: bool,
}

#[derive(uniffi::Record)]
pub struct GrepHit {
    pub path: String,
    pub rel: String,
    pub line: u64,
    pub text: String,
}

#[derive(uniffi::Record)]
pub struct GrepResponse {
    pub hits: Vec<GrepHit>,
    pub truncated: bool,
    pub files_scanned: u64,
}

pub fn to_canon(p: impl AsRef<Path>) -> String {
    p.as_ref().to_string_lossy().into_owned()
}

#[uniffi::export]
pub fn fs_read_dir(path: String, show_hidden: bool) -> Result<Vec<DirEntry>, BunError> {
    let root = PathBuf::from(&path);
    let read = std::fs::read_dir(&root).map_err(|e| e.to_string())?;

    let mut entries: Vec<DirEntry> = read
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            let (meta, was_symlink) = match std::fs::metadata(entry.path()) {
                Ok(m) => (Some(m), false),
                Err(_) => (entry.metadata().ok(), true),
            };
            let meta = meta?;

            let kind = if was_symlink {
                EntryKind::Symlink
            } else if meta.is_dir() {
                EntryKind::Dir
            } else {
                EntryKind::File
            };

            if name.starts_with('.') && !show_hidden {
                return None;
            }

            let size = meta.len();
            let mtime = meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0);

            Some(DirEntry {
                name,
                kind,
                size,
                mtime,
            })
        })
        .collect();

    entries.sort_by(|a, b| {
        let rank = |k: &EntryKind| match k {
            EntryKind::Dir => 0,
            EntryKind::Symlink => 1,
            EntryKind::File => 2,
        };
        rank(&a.kind)
            .cmp(&rank(&b.kind))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });

    Ok(entries)
}

#[uniffi::export]
pub fn fs_read_file(path: String) -> Result<ReadResult, BunError> {
    let p = PathBuf::from(&path);
    let meta = std::fs::metadata(&p).map_err(|e| e.to_string())?;

    let size = meta.len();
    if size > MAX_READ_BYTES {
        return Ok(ReadResult::TooLarge {
            size,
            limit: MAX_READ_BYTES,
        });
    }

    let bytes = std::fs::read(&p).map_err(|e| e.to_string())?;
    let sniff_len = bytes.len().min(BINARY_SNIFF_BYTES);
    if bytes[..sniff_len].contains(&0) {
        return Ok(ReadResult::Binary { size });
    }

    match String::from_utf8(bytes) {
        Ok(content) => Ok(ReadResult::Text { content, size }),
        Err(_) => Ok(ReadResult::Binary { size }),
    }
}

fn write_atomic(target: &Path, content: &[u8]) -> std::io::Result<()> {
    let parent = target.parent().ok_or_else(|| {
        std::io::Error::new(std::io::ErrorKind::InvalidInput, "path has no parent")
    })?;
    let mut tmp = NamedTempFile::new_in(parent)?;
    tmp.as_file_mut().write_all(content)?;
    tmp.as_file_mut().sync_all()?;
    tmp.persist(target).map_err(|e| e.error)?;
    Ok(())
}

#[uniffi::export]
pub fn fs_write_file(path: String, content: String) -> Result<(), BunError> {
    let target = PathBuf::from(&path);
    write_atomic(&target, content.as_bytes()).map_err(|e| e.to_string())?;
    Ok(())
}

#[uniffi::export]
pub fn fs_stat(path: String) -> Result<FileStat, BunError> {
    let p = PathBuf::from(&path);
    let meta = std::fs::metadata(&p).map_err(|e| e.to_string())?;
    let kind = if meta.is_dir() {
        StatKind::Dir
    } else if meta.file_type().is_symlink() {
        StatKind::Symlink
    } else {
        StatKind::File
    };
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    Ok(FileStat {
        size: meta.len(),
        mtime,
        kind,
    })
}

#[uniffi::export]
pub fn fs_canonicalize(path: String) -> Result<String, BunError> {
    let p = PathBuf::from(&path);
    let canon = std::fs::canonicalize(&p).map_err(|e| e.to_string())?;
    let s = canon.to_string_lossy().to_string();
    let s = s.strip_prefix(r"\\?\").unwrap_or(&s).to_string();
    Ok(s.replace('\\', "/"))
}

#[uniffi::export]
pub fn fs_create_file(path: String) -> Result<(), BunError> {
    let p = PathBuf::from(&path);
    if p.exists() {
        return Err(format!("already exists: {}", p.display()).into());
    }
    std::fs::write(&p, "").map_err(|e| e.to_string().into())
}

#[uniffi::export]
pub fn fs_create_dir(path: String) -> Result<(), BunError> {
    let p = PathBuf::from(&path);
    if p.exists() {
        return Err(format!("already exists: {}", p.display()).into());
    }
    std::fs::create_dir_all(&p).map_err(|e| e.to_string().into())
}

#[uniffi::export]
pub fn fs_rename(from_path: String, to_path: String) -> Result<(), BunError> {
    let from_p = PathBuf::from(&from_path);
    let to_p = PathBuf::from(&to_path);
    if !from_p.exists() {
        return Err(format!("not found: {}", from_p.display()).into());
    }
    if to_p.exists() {
        return Err(format!("already exists: {}", to_p.display()).into());
    }
    std::fs::rename(&from_p, &to_p).map_err(|e| e.to_string().into())
}

#[uniffi::export]
pub fn fs_delete(path: String) -> Result<(), BunError> {
    let p = PathBuf::from(&path);
    let meta = std::fs::symlink_metadata(&p).map_err(|e| e.to_string())?;

    let result = if meta.is_dir() {
        std::fs::remove_dir_all(&p)
    } else {
        std::fs::remove_file(&p)
    };
    result.map_err(|e| e.to_string().into())
}

#[uniffi::export]
pub fn fs_search(
    root: String,
    query: String,
    limit: Option<u32>,
    show_hidden: Option<bool>,
) -> Result<SearchResult, BunError> {
    let q = query.trim().to_lowercase();
    if q.is_empty() {
        return Ok(SearchResult {
            hits: Vec::new(),
            truncated: false,
        });
    }
    let cap = limit.unwrap_or(200).min(1000) as usize;
    let show_hidden = show_hidden.unwrap_or(false);
    let root_path = PathBuf::from(&root);
    if !root_path.is_dir() {
        return Err(format!("not a directory: {root}").into());
    }

    let mut out: Vec<SearchHit> = Vec::with_capacity(cap.min(64));
    let mut scanned: usize = 0;
    let mut truncated = false;

    let walker = WalkBuilder::new(&root_path)
        .hidden(!show_hidden)
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .ignore(true)
        .parents(true)
        .follow_links(false)
        .filter_entry(|dent| {
            if dent.depth() == 0 {
                return true;
            }
            match dent.file_name().to_str() {
                Some(name) => !PRUNE_DIRS.contains(&name),
                None => true,
            }
        })
        .build();

    for dent in walker.flatten() {
        scanned += 1;
        if scanned > MAX_SCANNED {
            truncated = true;
            break;
        }
        if out.len() >= cap {
            truncated = true;
            break;
        }
        let path = dent.path();
        if path == root_path {
            continue;
        }
        let rel = match path.strip_prefix(&root_path) {
            Ok(r) => to_canon(r),
            Err(_) => continue,
        };
        if !rel.to_lowercase().contains(&q) {
            continue;
        }
        let name = path
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        let is_dir = dent.file_type().map(|t| t.is_dir()).unwrap_or(false);
        out.push(SearchHit {
            path: to_canon(path),
            rel,
            name,
            is_dir,
        });
    }

    out.sort_by(|a, b| {
        let an = a.name.to_lowercase().contains(&q);
        let bn = b.name.to_lowercase().contains(&q);
        bn.cmp(&an).then(a.rel.len().cmp(&b.rel.len()))
    });

    Ok(SearchResult {
        hits: out,
        truncated,
    })
}

fn build_globset(patterns: &[String]) -> Result<Option<GlobSet>, BunError> {
    if patterns.is_empty() {
        return Ok(None);
    }
    let mut b = GlobSetBuilder::new();
    for p in patterns {
        let g = Glob::new(p).map_err(|e| format!("bad glob {p:?}: {e}"))?;
        b.add(g);
    }
    let set = b.build().map_err(|e| format!("globset build: {e}"))?;
    Ok(Some(set))
}

#[uniffi::export]
pub fn fs_grep(
    pattern: String,
    root: String,
    glob: Option<Vec<String>>,
    case_insensitive: Option<bool>,
    max_results: Option<u32>,
) -> Result<GrepResponse, BunError> {
    if pattern.is_empty() {
        return Err("empty pattern".into());
    }
    let root_path = PathBuf::from(&root);
    if !root_path.is_dir() {
        return Err(format!("not a directory: {root}").into());
    }
    let cap = max_results
        .unwrap_or(DEFAULT_MAX_RESULTS as u32)
        .clamp(1, HARD_MAX_RESULTS as u32) as usize;

    let matcher = RegexMatcherBuilder::new()
        .case_insensitive(case_insensitive.unwrap_or(false))
        .line_terminator(Some(b'\n'))
        .build(&pattern)
        .map_err(|e| format!("bad regex: {e}"))?;

    let globs = build_globset(glob.as_deref().unwrap_or(&[]))?;

    let walker = WalkBuilder::new(&root_path)
        .hidden(true)
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .ignore(true)
        .parents(true)
        .follow_links(false)
        .build_parallel();

    let hits: Arc<Mutex<Vec<GrepHit>>> = Arc::new(Mutex::new(Vec::new()));
    let scanned = Arc::new(AtomicUsize::new(0));
    let truncated = Arc::new(AtomicBool::new(false));

    walker.run(|| {
        let matcher = matcher.clone();
        let globs = globs.clone();
        let hits = hits.clone();
        let scanned = scanned.clone();
        let truncated = truncated.clone();
        let root_path = root_path.clone();

        Box::new(move |dent_res| {
            if truncated.load(Ordering::Relaxed) {
                return WalkState::Quit;
            }
            let dent = match dent_res {
                Ok(d) => d,
                Err(_) => return WalkState::Continue,
            };
            if !dent.file_type().map(|t| t.is_file()).unwrap_or(false) {
                return WalkState::Continue;
            }
            let path = dent.path();
            let rel = match path.strip_prefix(&root_path) {
                Ok(r) => to_canon(r),
                Err(_) => return WalkState::Continue,
            };
            if let Some(set) = globs.as_ref() {
                if !set.is_match(&rel) {
                    return WalkState::Continue;
                }
            }
            if let Ok(meta) = std::fs::metadata(path) {
                if meta.len() > FILE_SIZE_CAP {
                    return WalkState::Continue;
                }
            }

            scanned.fetch_add(1, Ordering::Relaxed);

            let abs = to_canon(path);
            let rel_clone = rel.clone();
            let mut searcher = SearcherBuilder::new()
                .binary_detection(BinaryDetection::quit(b'\x00'))
                .line_number(true)
                .build();

            let _ = searcher.search_path(
                &matcher,
                path,
                UTF8(|line_num, text| {
                    let line_text = text.trim_end_matches('\n').to_string();
                    let mut guard = hits.lock().unwrap();
                    if guard.len() >= cap {
                        truncated.store(true, Ordering::Relaxed);
                        return Ok(false);
                    }
                    guard.push(GrepHit {
                        path: abs.clone(),
                        rel: rel_clone.clone(),
                        line: line_num,
                        text: line_text,
                    });
                    Ok(true)
                }),
            );

            WalkState::Continue
        })
    });

    let final_hits = Arc::try_unwrap(hits)
        .map(|m| m.into_inner().unwrap())
        .unwrap_or_default();

    Ok(GrepResponse {
        hits: final_hits,
        truncated: truncated.load(Ordering::Relaxed),
        files_scanned: scanned.load(Ordering::Relaxed) as u64,
    })
}
