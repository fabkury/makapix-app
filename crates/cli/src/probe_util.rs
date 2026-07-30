//! Probe-spec helpers shared by the mkpx (engine) and mkps (scene) probe loops.

pub fn verdict(ok: bool) -> &'static str {
    if ok {
        "PASS"
    } else {
        "FAIL"
    }
}

pub fn idx(parts: &[&str], k: usize) -> usize {
    parts.get(k).and_then(|s| s.parse().ok()).unwrap_or(0)
}

pub fn iarg(parts: &[&str], k: usize) -> i32 {
    parts.get(k).and_then(|s| s.parse().ok()).unwrap_or(0)
}
