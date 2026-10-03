//! Lockfile guard for the fuzz crate (fuzzing-review W5).
//!
//! The fuzz crate is a detached workspace with its own `fuzz/Cargo.lock`, so nothing forces
//! it to resolve the same versions as the shipped build: before this guard, every WSL build
//! re-resolved `image`, `image-webp`, and `miniz_oxide` freely, and the fuzzed decoders were
//! not the shipped ones. `fuzz/Cargo.lock` is now the root lock plus the fuzz-only crates;
//! this test fails when any package the two lockfiles share carries different versions.
//! Refresh recipe: fuzz/README.md, "Toolchain and lockfile".

use std::collections::{BTreeMap, BTreeSet};

const ROOT: &str = include_str!("../../../Cargo.lock");
const FUZZ: &str = include_str!("../../../fuzz/Cargo.lock");

/// name → every version locked under that name.
fn packages(lock: &str) -> BTreeMap<String, BTreeSet<String>> {
    let mut out: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut name = None;
    for line in lock.lines() {
        let line = line.trim();
        if line == "[[package]]" {
            name = None;
        } else if let Some(v) = line.strip_prefix("name = ") {
            name = Some(v.trim_matches('"').to_string());
        } else if let Some(v) = line.strip_prefix("version = ") {
            if let Some(n) = name.take() {
                out.entry(n).or_default().insert(v.trim_matches('"').to_string());
            }
        }
    }
    out
}

#[test]
fn fuzz_lockfile_matches_the_shipped_versions() {
    let root = packages(ROOT);
    let fuzz = packages(FUZZ);
    assert!(root.contains_key("image") && fuzz.contains_key("image"), "lockfile parse broke");
    let drift: Vec<String> = root
        .iter()
        .filter_map(|(n, rv)| {
            let fv = fuzz.get(n)?;
            (fv != rv).then(|| format!("{n}: shipped {rv:?}, fuzzed {fv:?}"))
        })
        .collect();
    assert!(
        drift.is_empty(),
        "fuzz/Cargo.lock drifted from the root Cargo.lock (refresh it: fuzz/README.md):\n{}",
        drift.join("\n")
    );
    // The crates the fuzz targets exercise must actually be in the fuzz lock, not just agree
    // where they happen to overlap.
    for n in ["image", "image-webp", "miniz_oxide", "makapix-engine", "makapix-codec"] {
        assert!(fuzz.contains_key(n), "{n} missing from fuzz/Cargo.lock");
    }
}
