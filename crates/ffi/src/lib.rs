//! C ABI bridge (SPEC §19). A `Session` lives behind an opaque pointer; the Flutter shell
//! drives it with DSL command strings and pulls composited RGBA bytes for display. No
//! panics cross the boundary (errors are returned as strings / status codes).

// Every `extern "C"` export here necessarily dereferences raw pointers handed across the C ABI
// from Dart; that is the whole point of this crate. Marking each `unsafe` would not change the
// C ABI and only adds noise, so we allow the lint crate-wide (the contract is documented per fn).
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use makapix_engine::geom::{MAX_DIM, MIN_DIM};
use makapix_engine::Session;
use std::ffi::{c_char, CStr, CString};
use std::os::raw::c_int;
use std::slice;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

// ---- export progress / cancel ----
//
// The multi-frame exports (GIF/WebP) run on a background isolate in the shell while the UI
// isolate polls for progress; both isolates load this same library, so a pair of process-wide
// atomics bridges them. done/total are packed into ONE atomic (high 32 = total, low 32 = done)
// so a poll always reads a consistent pair. Each export resets both atomics when it starts, so
// nothing leaks between exports (the shell's modal dialog ensures at most one runs at a time).
static EXPORT_PROGRESS: AtomicU64 = AtomicU64::new(0);
static EXPORT_CANCEL: AtomicBool = AtomicBool::new(false);

fn export_progress_set(done: u32, total: u32) {
    EXPORT_PROGRESS.store(((total as u64) << 32) | done as u64, Ordering::Relaxed);
}

/// Progress of the multi-frame export in flight, packed as (total << 32) | done. A step is one
/// frame composited or one frame encoded, so total = 2 × frames. 0 = no export started.
#[no_mangle]
pub extern "C" fn mkpx_export_progress() -> u64 {
    EXPORT_PROGRESS.load(Ordering::Relaxed)
}

/// Clear the progress pair. The shell calls this right before spawning an export so a poll never
/// briefly shows the PREVIOUS export's finished bar while the new isolate is still starting.
#[no_mangle]
pub extern "C" fn mkpx_export_progress_reset() {
    EXPORT_PROGRESS.store(0, Ordering::Relaxed);
}

/// Ask the export in flight to stop at its next frame boundary; its export call returns null.
#[no_mangle]
pub extern "C" fn mkpx_export_cancel() {
    EXPORT_CANCEL.store(true, Ordering::Relaxed);
}

/// Create a new session with a `w×h` document. Returns an opaque pointer (null on bad args).
#[no_mangle]
pub extern "C" fn mkpx_new(w: u16, h: u16) -> *mut Session {
    if !(MIN_DIM..=MAX_DIM).contains(&w) || !(MIN_DIM..=MAX_DIM).contains(&h) {
        return std::ptr::null_mut();
    }
    Box::into_raw(Box::new(Session::new(w, h)))
}

/// Free a session created by `mkpx_new`.
#[no_mangle]
pub extern "C" fn mkpx_free(ptr: *mut Session) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)) };
    }
}

fn session<'a>(ptr: *mut Session) -> Option<&'a mut Session> {
    if ptr.is_null() {
        None
    } else {
        Some(unsafe { &mut *ptr })
    }
}

/// Run a DSL script (UTF-8, `len` bytes). Returns null on success or a malloc'd C error
/// string (free with `mkpx_free_string`).
#[no_mangle]
pub extern "C" fn mkpx_run(ptr: *mut Session, script: *const u8, len: usize) -> *mut c_char {
    let s = match session(ptr) {
        Some(s) => s,
        None => return cstring("null session"),
    };
    let bytes = unsafe { slice::from_raw_parts(script, len) };
    let src = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return cstring("invalid utf-8"),
    };
    match s.run_script(src) {
        Ok(()) => std::ptr::null_mut(),
        Err(e) => cstring(&e),
    }
}

#[no_mangle]
pub extern "C" fn mkpx_width(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.size().0 as u32).unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn mkpx_height(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.size().1 as u32).unwrap_or(0)
}
/// The size of the buffer `mkpx_display` fills: the whole storage (canvas + gutter) when the overscan
/// view is on, else the canvas. The shell sizes its texture + outline buffer from these.
#[no_mangle]
pub extern "C" fn mkpx_display_width(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.display_size().0).unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn mkpx_display_height(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.display_size().1).unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn mkpx_frame_count(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.doc.frames.len() as u32).unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn mkpx_active_frame(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.doc.active_frame as u32).unwrap_or(0)
}
#[no_mangle]
pub extern "C" fn mkpx_play_frame(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.current_play_frame() as u32).unwrap_or(0)
}

/// Fill `out` (capacity `cap` bytes) with the active frame's display RGBA. Returns bytes
/// written, or -1 if the buffer is too small.
#[no_mangle]
pub extern "C" fn mkpx_display(
    ptr: *mut Session,
    onion: c_int,
    grid: c_int,
    checker: c_int,
    out: *mut u8,
    cap: usize,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.display_bytes(onion != 0, grid != 0, checker != 0);
    if bytes.len() > cap || out.is_null() {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()).copy_from_slice(&bytes) };
    bytes.len() as c_int
}

/// Fill `out` with a specific frame's composited RGBA (no overlays).
#[no_mangle]
pub extern "C" fn mkpx_composite_frame(ptr: *mut Session, frame: u32, out: *mut u8, cap: usize) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.composite_frame_bytes(frame as usize);
    if bytes.len() > cap || out.is_null() {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()).copy_from_slice(&bytes) };
    bytes.len() as c_int
}

/// Fill `out` with 1-byte-per-pixel selection coverage (1=selected) for the shell to draw a
/// thin animated outline. Returns bytes written (= w*h), or 0 when there's nothing to outline.
#[no_mangle]
pub extern "C" fn mkpx_outline_mask(ptr: *mut Session, out: *mut u8, cap: usize) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    if out.is_null() {
        return -1;
    }
    let slice = unsafe { slice::from_raw_parts_mut(out, cap) };
    s.outline_mask_bytes(slice) as c_int
}

/// 1 when `mkpx_outline_mask` could return a non-empty mask, else 0 — a cheap presence
/// check (no mask is built) so the shell can skip the whole fetch on the plain-drawing
/// hot path. Conservative: may report 1 for a draft that resolves empty, never 0 for a
/// non-empty outline. [battery F13]
#[no_mangle]
pub extern "C" fn mkpx_outline_present(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.outline_present() as u32).unwrap_or(0)
}

/// Packed playback status: high 32 bits = the current play frame, low 32 = µs until the
/// visible frame can next change (capped at u32::MAX; a lower bound — see
/// `Session::play_status`). One O(log frames) scalar call replaces the per-vsync
/// `mkpx_play_frame` poll and powers the shell's hybrid ticker/timer playback clock.
/// [battery F15/R3]
#[no_mangle]
pub extern "C" fn mkpx_play_status(ptr: *mut Session) -> u64 {
    match session(ptr) {
        Some(s) => {
            let (frame, us) = s.play_status();
            ((frame as u64) << 32) | us.min(u32::MAX as u64)
        }
        None => 0,
    }
}

/// Content hash (low 64 bits) of a frame — for caching film-roll thumbnails.
#[no_mangle]
pub extern "C" fn mkpx_frame_hash(ptr: *mut Session, frame: u32) -> u64 {
    session(ptr).map(|s| s.frame_hash(frame as usize)).unwrap_or(0)
}

/// Fill `out` with a `tw`×`th` nearest-downscaled composite of `frame` (straight RGBA).
/// Returns bytes written, or -1 if the buffer is too small.
#[no_mangle]
pub extern "C" fn mkpx_frame_thumb(
    ptr: *mut Session,
    frame: u32,
    tw: u32,
    th: u32,
    out: *mut u8,
    cap: usize,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.frame_thumb_bytes(frame as usize, tw, th);
    if bytes.len() > cap || out.is_null() {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()).copy_from_slice(&bytes) };
    bytes.len() as c_int
}

/// Content hash (low 64 bits) of a single layer — for caching layer film-strip thumbnails.
#[no_mangle]
pub extern "C" fn mkpx_layer_hash(ptr: *mut Session, frame: u32, layer: u32) -> u64 {
    session(ptr)
        .map(|s| s.layer_thumb_hash(frame as usize, layer as usize))
        .unwrap_or(0)
}

/// Fill `out` with a `tw`×`th` nearest-downscaled thumbnail of a single layer (straight RGBA,
/// transparent where empty). Returns bytes written, or -1 if the buffer is too small.
#[no_mangle]
pub extern "C" fn mkpx_layer_thumb(
    ptr: *mut Session,
    frame: u32,
    layer: u32,
    tw: u32,
    th: u32,
    out: *mut u8,
    cap: usize,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.layer_thumb_bytes(frame as usize, layer as usize, tw, th);
    if bytes.is_empty() || bytes.len() > cap || out.is_null() {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()).copy_from_slice(&bytes) };
    bytes.len() as c_int
}

/// Return the document state as a malloc'd JSON C string (free with `mkpx_free_string`).
#[no_mangle]
pub extern "C" fn mkpx_state_json(ptr: *mut Session) -> *mut c_char {
    match session(ptr) {
        Some(s) => cstring(&s.state_json()),
        None => cstring("{}"),
    }
}

/// Engine-accounted memory census (tile-deduped; see `probe::mem_report`) as JSON. Free with
/// `mkpx_free_string`. Powers the in-app memory stress lab.
#[no_mangle]
pub extern "C" fn mkpx_mem_json(ptr: *mut Session) -> *mut c_char {
    match session(ptr) {
        Some(s) => cstring(&s.mem_json()),
        None => cstring("{}"),
    }
}

/// Unique colors used by the artwork as JSON: `{"colors":["#RRGGBBAA",...]}` or
/// `{"over_limit":true}` past 256 uniques (early abort). Free with `mkpx_free_string`.
#[no_mangle]
pub extern "C" fn mkpx_used_colors_json(ptr: *mut Session) -> *mut c_char {
    match session(ptr) {
        Some(s) => cstring(&s.used_colors_json()),
        None => cstring("{}"),
    }
}

/// Upper-bound estimate of the `.mkpx` payload the document saves to (bytes) — check before
/// `mkpx_save` on constrained platforms (SPEC §8.2b).
#[no_mangle]
pub extern "C" fn mkpx_save_estimate(ptr: *mut Session) -> u64 {
    session(ptr).map(|s| s.save_estimate_bytes() as u64).unwrap_or(0)
}

/// Primary color as 0xRRGGBBAA.
#[no_mangle]
pub extern "C" fn mkpx_primary_color(ptr: *mut Session) -> u32 {
    session(ptr)
        .map(|s| {
            let c = s.settings.primary;
            ((c.r as u32) << 24) | ((c.g as u32) << 16) | ((c.b as u32) << 8) | c.a as u32
        })
        .unwrap_or(0)
}

/// Serialize the document to `.mkpx`. Returns a malloc'd buffer; writes its length to
/// `out_len`. Free with `mkpx_free_bytes(ptr, len)`.
#[no_mangle]
pub extern "C" fn mkpx_save(ptr: *mut Session, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let bytes = s.save_bytes().into_boxed_slice();
    let len = bytes.len();
    if !out_len.is_null() {
        unsafe { *out_len = len as u64 };
    }
    Box::into_raw(bytes) as *mut u8
}

// mkpx_load return codes — keep in sync with `LoadStatus` / `loadStatusFromRc` in
// app/lib/engine_ffi.dart.
const LOAD_OK: c_int = 0;
const LOAD_WARN_HASH: c_int = 1;
const LOAD_ERR_OTHER: c_int = -1;
const LOAD_ERR_NOT_MKPX: c_int = -2;
const LOAD_ERR_UNSUPPORTED: c_int = -3;
const LOAD_ERR_CORRUPT: c_int = -4;
const LOAD_ERR_OVER_BUDGET: c_int = -5;

/// Exhaustive on purpose: a new `IoError` variant must pick its code here, not fall to `-1`.
fn load_error_code(e: &makapix_engine::io::IoError) -> c_int {
    use makapix_engine::io::IoError;
    match e {
        IoError::BadMagic => LOAD_ERR_NOT_MKPX,
        // An unknown critical chunk is a newer-writer artifact, same as a newer version.
        IoError::UnsupportedVersion(_) | IoError::UnsupportedChunk(_) => LOAD_ERR_UNSUPPORTED,
        // TooLarge is the crafted-input caps (spec §19), not the budget — corrupt for shells.
        IoError::Incomplete | IoError::Corrupt(_) | IoError::TooLarge(_) => LOAD_ERR_CORRUPT,
        IoError::OverBudget => LOAD_ERR_OVER_BUDGET,
    }
}

fn compact_error_code(e: &makapix_codec::mkpx_compact::CompactError) -> c_int {
    use makapix_codec::mkpx_compact::CompactError;
    match e {
        CompactError::BadMagic => LOAD_ERR_NOT_MKPX,
        // TooLarge here is the inflate bomb guard — crafted input, so corrupt.
        CompactError::TooLarge | CompactError::Corrupt => LOAD_ERR_CORRUPT,
    }
}

/// Load a `.mkpx` document from bytes — accepts both the **plain** container and the **compact**
/// (DEFLATE) envelope, auto-detected by signature.
///
/// Return codes (keep in sync with `LoadStatus` / `loadStatusFromRc` in app/lib/engine_ffi.dart):
/// - `0` — loaded, fully consistent.
/// - `1` — loaded **with warnings**: the stored content hash didn't match the rebuilt document.
///   Diagnostic only (e.g. the file was written by a build with a newer hash rule); the document
///   is installed and fully usable — shells should log, never block.
/// - `-1` — other failure (null session).
/// - `-2` — not a `.mkpx` file (neither the plain nor the compact signature).
/// - `-3` — unsupported: a newer/unknown format version, or an unknown critical chunk.
/// - `-4` — corrupt: CRC mismatch, truncation, a structural bound/cap violation, or a corrupt
///   compact envelope.
/// - `-5` — refused: the document would exceed the session's memory budget (SPEC §8.2b).
///
/// On any negative return the session's document is unchanged.
#[no_mangle]
pub extern "C" fn mkpx_load(ptr: *mut Session, data: *const u8, len: usize) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return LOAD_ERR_OTHER,
    };
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    fn finish(s: &mut Session, plain: &[u8]) -> c_int {
        match s.load_bytes_tolerant(plain) {
            Ok(w) if w.is_empty() => LOAD_OK,
            Ok(_) => LOAD_WARN_HASH,
            Err(e) => load_error_code(&e),
        }
    }
    if makapix_codec::mkpx_compact::is_compact(bytes) {
        // Inflate the compact envelope at the periphery, then load the plain bytes in the engine.
        match makapix_codec::mkpx_compact::open(bytes) {
            Ok(plain) => finish(s, &plain),
            Err(e) => compact_error_code(&e),
        }
    } else {
        // Plain container (or garbage → BadMagic from the engine loader) — load directly, no copy.
        finish(s, bytes)
    }
}

/// Serialize the document to a **compact** (DEFLATE-wrapped) `.mkpx`, for explicit "Save" / export.
/// The 10 s autosave should use [`mkpx_save`] (plain, cheap). Returns a malloc'd buffer; writes its
/// length to `out_len`. Free with `mkpx_free_bytes(ptr, len)`.
#[no_mangle]
pub extern "C" fn mkpx_save_compact(ptr: *mut Session, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let plain = s.save_bytes();
    let bytes = makapix_codec::mkpx_compact::compress(&plain).into_boxed_slice();
    let len = bytes.len();
    if !out_len.is_null() {
        unsafe { *out_len = len as u64 };
    }
    Box::into_raw(bytes) as *mut u8
}

/// Shared tail of the two import entry points: build the `ImportConfig` and apply decoded frames
/// to the live session. Returns 0 on success, -1 on empty input, -2 when the memory-budget gate
/// rolled the import back (a refusal is registered on the session).
#[allow(clippy::too_many_arguments)]
fn import_frames_into(
    s: &mut Session,
    frames: &[makapix_engine::import::DecodedFrame],
    mode: c_int,
    as_layer: c_int,
    start_frame: u32,
    crop_x: i32,
    crop_y: i32,
    crop_w: i32,
    crop_h: i32,
) -> c_int {
    use makapix_engine::geom::IRect;
    use makapix_engine::import::{Anchor, ImportConfig, ScaleMode};
    if frames.is_empty() {
        return -1;
    }
    let crop_rect = if crop_w > 0 && crop_h > 0 {
        Some(IRect::new(crop_x, crop_y, crop_w as u32, crop_h as u32))
    } else {
        None
    };
    let cfg = ImportConfig {
        mode: match mode {
            1 => ScaleMode::Stretch,
            2 => ScaleMode::Crop,
            _ => ScaleMode::Fit,
        },
        anchor: Anchor::Center,
        start_frame: start_frame as usize,
        as_layer: as_layer != 0,
        crop_rect,
    };
    if s.import_decoded(frames, cfg) {
        0
    } else {
        -2
    }
}

/// Import an image file (GIF/PNG/APNG/JPEG/BMP/WebP) into the document.
/// `mode`: 0=Fit, 1=Stretch, 2=Crop. `as_layer`: 0/1. A non-empty crop rect (`crop_w>0 && crop_h>0`,
/// source pixels) places that region 1:1 centered on the canvas (downscaled to fit only when larger,
/// never upscaled), overriding `mode`. Returns 0 on success, -1 on decode failure, -2 when the
/// memory-budget gate refused the import (document unchanged), -3 when the input is valid but
/// exceeds the codec's decode size limits (too large — worth telling apart from corrupt).
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn mkpx_import(
    ptr: *mut Session,
    data: *const u8,
    len: usize,
    mode: c_int,
    as_layer: c_int,
    start_frame: u32,
    crop_x: i32,
    crop_y: i32,
    crop_w: i32,
    crop_h: i32,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    let frames = match makapix_codec::decode(bytes) {
        Ok(f) => f,
        Err(makapix_codec::CodecError::TooLarge(_)) => return -3,
        Err(_) => return -1,
    };
    import_frames_into(s, &frames, mode, as_layer, start_frame, crop_x, crop_y, crop_w, crop_h)
}

// ---- background-decode import (audit #3, off-isolate half) ----
//
// The decode is the expensive part of an image import (LZW/inflate/VP8L over up to 1024 frames,
// capped at 384 MiB decoded), and `mkpx_import` runs it synchronously on whichever thread calls
// it — on the shell's UI isolate that froze the editor for seconds. These two functions split the
// seam: `mkpx_decode_image` needs NO session, so the shell runs it on a background isolate and
// hands the resulting native buffer's ADDRESS back to the UI isolate (both isolates load this
// same library, so the buffer lives in shared process memory — the same property the export
// progress atomics rely on); `mkpx_import_decoded` then applies it to the live session, which is
// only placement blits. The opaque session pointer still never crosses isolates (audit F-12).

/// Decode an image file (GIF/PNG/APNG/JPEG/BMP/WebP) into a flat decoded-frames blob, with no
/// session involved. Blob layout (all integers little-endian u32):
/// `[frame_count]` then per frame `[w][h][duration_us][w*h*4 straight-RGBA bytes]`.
/// Returns a malloc'd buffer (free with `mkpx_free_bytes`) or null on decode failure. When
/// `out_status` is non-null it receives 0 on success, -1 on decode failure (undecodable or
/// corrupt input), or -3 when the input is valid but exceeds the codec's decode size limits —
/// the same codes `mkpx_import` returns, so callers can tell "too large" apart from "corrupt".
#[no_mangle]
pub extern "C" fn mkpx_decode_image(
    data: *const u8,
    len: usize,
    out_len: *mut u64,
    out_status: *mut c_int,
) -> *mut u8 {
    let set_status = |s: c_int| {
        if !out_status.is_null() {
            unsafe { *out_status = s };
        }
    };
    set_status(-1);
    if data.is_null() {
        return std::ptr::null_mut();
    }
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    let frames = match makapix_codec::decode(bytes) {
        Ok(f) => f,
        Err(makapix_codec::CodecError::TooLarge(_)) => {
            set_status(-3);
            return std::ptr::null_mut();
        }
        Err(_) => return std::ptr::null_mut(),
    };
    set_status(0);
    let total: usize = 4 + frames.iter().map(|f| 12 + f.rgba.len()).sum::<usize>();
    let mut v = Vec::with_capacity(total);
    v.extend_from_slice(&(frames.len() as u32).to_le_bytes());
    for f in &frames {
        v.extend_from_slice(&f.w.to_le_bytes());
        v.extend_from_slice(&f.h.to_le_bytes());
        v.extend_from_slice(&f.duration_us.to_le_bytes());
        v.extend_from_slice(&f.rgba);
    }
    bytes_out(v, out_len)
}

/// Apply a `mkpx_decode_image` blob to the document — the placement half of `mkpx_import`, same
/// `mode`/`as_layer`/crop semantics. The blob is parsed defensively (strict lengths, checked
/// arithmetic), so a corrupt buffer fails cleanly instead of panicking across the boundary.
/// Returns 0 on success, -1 on a malformed blob, -2 when the memory-budget gate refused the
/// import (document unchanged). The caller still owns the blob (free with `mkpx_free_bytes`).
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn mkpx_import_decoded(
    ptr: *mut Session,
    blob: *const u8,
    len: usize,
    mode: c_int,
    as_layer: c_int,
    start_frame: u32,
    crop_x: i32,
    crop_y: i32,
    crop_w: i32,
    crop_h: i32,
) -> c_int {
    use makapix_engine::import::DecodedFrame;
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    if blob.is_null() {
        return -1;
    }
    let b = unsafe { slice::from_raw_parts(blob, len) };
    let read_u32 = |at: usize| -> Option<u32> {
        b.get(at..at + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
    };
    let count = match read_u32(0) {
        Some(c) => c as usize,
        None => return -1,
    };
    let mut frames = Vec::new();
    let mut at = 4usize;
    for _ in 0..count {
        let (w, h, duration_us) = match (read_u32(at), read_u32(at + 4), read_u32(at + 8)) {
            (Some(w), Some(h), Some(d)) => (w, h, d),
            _ => return -1,
        };
        let px = match (w as u64).checked_mul(h as u64).and_then(|n| n.checked_mul(4)) {
            Some(n) if w > 0 && h > 0 && n <= (len as u64) => n as usize,
            _ => return -1,
        };
        at += 12;
        let end = match at.checked_add(px) {
            Some(e) => e,
            None => return -1,
        };
        let rgba = match b.get(at..end) {
            Some(s) => s.to_vec(),
            None => return -1,
        };
        at = end;
        frames.push(DecodedFrame { rgba, w, h, duration_us });
    }
    if at != len {
        return -1;
    }
    import_frames_into(s, &frames, mode, as_layer, start_frame, crop_x, crop_y, crop_w, crop_h)
}

/// Upscale (nearest-neighbor) then encode one frame's RGBA as PNG or lossless WebP, with coarse
/// 2-step progress (composite/extract done → encode done) and a cancel check between the steps.
/// The shared tail of the four single-frame exports.
fn still_out(w: u16, h: u16, rgba: Vec<u8>, scale: u32, webp: bool, out_len: *mut u64) -> *mut u8 {
    let scale = scale.clamp(1, 32);
    export_progress_set(1, 2);
    if EXPORT_CANCEL.load(Ordering::Relaxed) {
        return std::ptr::null_mut();
    }
    let data = if scale == 1 { rgba } else { makapix_codec::upscale_nearest(w as u32, h as u32, &rgba, scale) };
    let (ow, oh) = (w as u32 * scale, h as u32 * scale);
    let encoded =
        if webp { makapix_codec::encode_webp(ow, oh, &data) } else { makapix_codec::encode_png(ow, oh, &data) };
    let out = match encoded {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    };
    export_progress_set(2, 2);
    out
}

/// One composited frame as a still (PNG or lossless WebP): the body of the two frame exports.
fn export_frame_still(ptr: *mut Session, frame: u32, scale: u32, webp: bool, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    export_progress_set(0, 2);
    let rgba = s.composite_frame_bytes(frame as usize);
    still_out(w, h, rgba, scale, webp, out_len)
}

/// One layer of one frame as a still — the layer's own pixels (straight alpha), not the
/// composite: the body of the two layer exports. Stale indices clamp (bounds-safe); null when
/// the frame has no layers.
fn export_layer_still(ptr: *mut Session, frame: u32, layer: u32, scale: u32, webp: bool, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    export_progress_set(0, 2);
    let rgba = s.layer_rgba_bytes(frame as usize, layer as usize);
    if rgba.is_empty() {
        return std::ptr::null_mut();
    }
    still_out(w, h, rgba, scale, webp, out_len)
}

/// Export the active (or given) frame as PNG, upscaled ×`scale` (nearest-neighbor, clamped
/// 1..=32). Returns a malloc'd buffer; len via `out_len`.
#[no_mangle]
pub extern "C" fn mkpx_export_png(ptr: *mut Session, frame: u32, scale: u32, out_len: *mut u64) -> *mut u8 {
    export_frame_still(ptr, frame, scale, false, out_len)
}

/// Export the active (or given) frame as a LOSSLESS static WebP, upscaled ×`scale` — the still
/// twin of `mkpx_export_png` (for artwork whose colors exceed formats like GIF; distinct from
/// `mkpx_export_webp`, which exports the whole animation).
#[no_mangle]
pub extern "C" fn mkpx_export_frame_webp(ptr: *mut Session, frame: u32, scale: u32, out_len: *mut u64) -> *mut u8 {
    export_frame_still(ptr, frame, scale, true, out_len)
}

/// Export ONE layer of one frame as a PNG — the layer's own pixels (straight alpha), not the
/// composite — upscaled ×`scale` (nearest-neighbor, clamped 1..=32). Stale indices clamp
/// (bounds-safe). Returns a malloc'd buffer; len via `out_len`; null when the frame has no
/// layers or on encode failure.
#[no_mangle]
pub extern "C" fn mkpx_export_layer_png(ptr: *mut Session, frame: u32, layer: u32, scale: u32, out_len: *mut u64) -> *mut u8 {
    export_layer_still(ptr, frame, layer, scale, false, out_len)
}

/// Export ONE layer of one frame as a LOSSLESS static WebP — the still twin of
/// `mkpx_export_layer_png`.
#[no_mangle]
pub extern "C" fn mkpx_export_layer_webp(ptr: *mut Session, frame: u32, layer: u32, scale: u32, out_len: *mut u64) -> *mut u8 {
    export_layer_still(ptr, frame, layer, scale, true, out_len)
}

/// Advance the export's "done" counter by one step (one frame composited, or one frame encoded).
/// Total steps = 2n (composite + encode per frame). `done` never approaches the 32-bit width, so a
/// plain increment of the packed atomic's low word is safe. [audit #10 streaming export]
fn export_progress_inc() {
    EXPORT_PROGRESS.fetch_add(1, Ordering::Relaxed);
}

/// The streaming encoders' per-frame hook: one encode step done, and `false` (= abort) once cancel
/// is set. (Composite steps are counted by the frame-source closure in each export fn.)
fn encode_progress_hook_streaming(_done: usize, _total: usize) -> bool {
    export_progress_inc();
    !EXPORT_CANCEL.load(Ordering::Relaxed)
}

/// Cheap upfront guard on the whole-animation output size. Since the export now streams one frame at
/// a time (no all-frames flatten — audit #10), this no longer bounds a resident RGBA buffer; it
/// stays as a defense-in-depth sanity bound (also indirectly bounds the compressed WebP
/// accumulation). With the document budget in force the worst legal case is well under the cap.
fn export_flatten_ok(s: &Session) -> bool {
    const EXPORT_FLATTEN_CAP: usize = 768 * 1024 * 1024;
    let (w, h) = s.size();
    s.doc.frames.len().saturating_mul(w as usize * h as usize * 4) <= EXPORT_FLATTEN_CAP
}

/// Export all frames as an animated GIF, upscaled ×`scale` (nearest-neighbor, clamped 1..=32,
/// applied one frame at a time). Frames are composited **on demand** and fed to the encoder one at
/// a time, so no all-frames RGBA flatten is ever resident (audit #10). Returns a malloc'd buffer;
/// len via `out_len`. Progress via `mkpx_export_progress`; null on failure OR `mkpx_export_cancel`.
#[no_mangle]
pub extern "C" fn mkpx_export_gif(ptr: *mut Session, scale: u32, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    if !export_flatten_ok(s) {
        return std::ptr::null_mut();
    }
    let (w, h) = s.size();
    let n = s.doc.frames.len();
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    export_progress_set(0, 2 * n as u32);
    let s_ref: &Session = s;
    let mut i = 0usize;
    let next = || {
        if i >= n {
            return None;
        }
        let frame = (s_ref.composite_frame_bytes(i), s_ref.doc.frames[i].duration_us);
        i += 1;
        export_progress_inc(); // one composite step done
        Some(frame)
    };
    match makapix_codec::encode_gif_streaming(w as u32, h as u32, n, next, scale, &mut encode_progress_hook_streaming) {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Export the artwork as a LOSSLESS WebP (static for one frame, animated WebP for many) — the
/// recommended format for Makapix Club submissions — upscaled ×`scale` (nearest-neighbor,
/// clamped 1..=32). Composited on demand, one frame at a time (audit #10). Returns a malloc'd
/// buffer; len via `out_len`. Progress via `mkpx_export_progress`; null on failure OR cancel.
#[no_mangle]
pub extern "C" fn mkpx_export_webp(ptr: *mut Session, scale: u32, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    if !export_flatten_ok(s) {
        return std::ptr::null_mut();
    }
    let (w, h) = s.size();
    let n = s.doc.frames.len();
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    export_progress_set(0, 2 * n as u32);
    let s_ref: &Session = s;
    let mut i = 0usize;
    let next = || {
        if i >= n {
            return None;
        }
        let frame = (s_ref.composite_frame_bytes(i), s_ref.doc.frames[i].duration_us);
        i += 1;
        export_progress_inc();
        Some(frame)
    };
    match makapix_codec::encode_animated_webp_streaming(w as u32, h as u32, n, next, scale, &mut encode_progress_hook_streaming) {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

// ---- replay checkpoints (Journal scrubbing; session/checkpoint.rs) ----

/// Take a replay checkpoint of the current state. Returns the checkpoint's STABLE id
/// (>= 0), or -1 when the session is mid-gesture/draft (caller retries at the next journal
/// line) or null. Ids are monotone in take order; older checkpoints may be evicted by the
/// byte budget — resync with `mkpx_checkpoint_ids` after any take.
#[no_mangle]
pub extern "C" fn mkpx_checkpoint_take(ptr: *mut Session) -> i64 {
    session(ptr).and_then(|s| s.take_checkpoint()).map(|id| id as i64).unwrap_or(-1)
}

/// Restore checkpoint `id`. 0 = restored; -1 = unknown id (evicted/cleared) or null session.
/// The checkpoint is retained — restore is repeatable (the scrub loop).
#[no_mangle]
pub extern "C" fn mkpx_checkpoint_restore(ptr: *mut Session, id: u32) -> c_int {
    match session(ptr) {
        Some(s) => {
            if s.restore_checkpoint(id) {
                0
            } else {
                -1
            }
        }
        None => -1,
    }
}

/// Number of live checkpoints (0 on null session).
#[no_mangle]
pub extern "C" fn mkpx_checkpoint_count(ptr: *mut Session) -> u32 {
    session(ptr).map(|s| s.checkpoint_count() as u32).unwrap_or(0)
}

/// Write up to `cap` live checkpoint ids (ascending) into `out`; returns the LIVE count
/// (which may exceed what was written when `cap` is small — call with cap = 512, the
/// engine's MAX_CHECKPOINTS, and it always suffices).
#[no_mangle]
pub extern "C" fn mkpx_checkpoint_ids(ptr: *mut Session, out: *mut u32, cap: u32) -> u32 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return 0,
    };
    let n = s.checkpoint_count() as u32;
    if !out.is_null() && cap > 0 {
        let dst = unsafe { slice::from_raw_parts_mut(out, cap as usize) };
        for (i, id) in s.checkpoint_ids().take(cap as usize).enumerate() {
            dst[i] = id;
        }
    }
    n
}

/// Drop every checkpoint, freeing the retained tiles (e.g. when the Replay view closes).
#[no_mangle]
pub extern "C" fn mkpx_checkpoint_clear(ptr: *mut Session) {
    if let Some(s) = session(ptr) {
        s.clear_checkpoints();
    }
}

/// The document content hash as a 32-lowercase-hex string. A validation aid for the replay
/// driver (seek-vs-straight-run comparisons) — NOT a crash-sync marker: it deliberately
/// excludes palettes/active_frame/selection (the shell's markers hash the saved bytes
/// instead). Free with `mkpx_free_string`; null on null session.
#[no_mangle]
pub extern "C" fn mkpx_doc_hash(ptr: *mut Session) -> *mut c_char {
    match session(ptr) {
        Some(s) => cstring(&makapix_engine::util::hash_hex(s.doc.content_hash())),
        None => std::ptr::null_mut(),
    }
}

// ---- timelapse export (docs/replay/ANALYSIS.md §4; ADR 0004) ----

struct TimelapseOverlay {
    rgba: Vec<u8>,
    w: u32,
    h: u32,
    x: i32,
    y: i32,
}

/// The registered timelapse overlay (the finale wordmark). Process-wide by design, like
/// EXPORT_PROGRESS/EXPORT_CANCEL: the shell runs at most one export at a time, and both
/// assumptions break together if that ever changes.
static TIMELAPSE_OVERLAY: std::sync::Mutex<Option<TimelapseOverlay>> = std::sync::Mutex::new(None);

/// Register (or clear) the process-wide timelapse overlay, blitted straight-alpha onto every
/// subsequent `mkpx_timelapse_frame` at (`x`,`y`) in OUTPUT coordinates, clipped. Pass a null
/// `rgba` (or zero `w`/`h`) to clear. The pixels are copied — the caller may free
/// immediately. Returns 0 ok, -1 on oversize (w or h > 2048) or a length mismatch.
#[no_mangle]
pub extern "C" fn mkpx_timelapse_set_overlay(rgba: *const u8, w: u32, h: u32, x: i32, y: i32) -> c_int {
    let mut slot = TIMELAPSE_OVERLAY.lock().expect("overlay lock poisoned");
    if rgba.is_null() || w == 0 || h == 0 {
        *slot = None;
        return 0;
    }
    if w > 2048 || h > 2048 {
        return -1;
    }
    let len = (w as usize) * (h as usize) * 4;
    let src = unsafe { slice::from_raw_parts(rgba, len) };
    *slot = Some(TimelapseOverlay { rgba: src.to_vec(), w, h, x, y });
    0
}

/// Produce ONE timelapse output frame from the CURRENT session state:
/// composite(`frame`) → flatten over `bg` → integer NN upscale ×`scale` (clamped 1..=32) →
/// center-pad onto an `out_w`×`out_h` bg-filled canvas → blit the registered overlay (if
/// any) → return RGBA8888 (`format` 0) or tightly-packed I420/BT.601-limited (`format` 1;
/// requires even `out_w`/`out_h`; the centering offset is floored to even for chroma
/// alignment). `bg_rgba` is 0xRRGGBBAA; its alpha is ignored (padding is opaque).
/// Returns a malloc'd buffer (free with `mkpx_free_bytes`); len via `out_len` (RGBA:
/// `out_w*out_h*4`; I420: `out_w*out_h*3/2`). Null on: null session, the scaled size
/// exceeding `out_w`/`out_h`, odd I420 dimensions, or an unknown format. Does NOT touch
/// EXPORT_PROGRESS/EXPORT_CANCEL — the shell's replay-export loop owns pacing and cancel
/// (it simply stops calling).
#[no_mangle]
pub extern "C" fn mkpx_timelapse_frame(
    ptr: *mut Session,
    frame: u32,
    scale: u32,
    out_w: u32,
    out_h: u32,
    bg_rgba: u32,
    format: c_int,
    out_len: *mut u64,
) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    if format != 0 && format != 1 {
        return std::ptr::null_mut();
    }
    if format == 1 && (out_w % 2 != 0 || out_h % 2 != 0) {
        return std::ptr::null_mut();
    }
    let scale = scale.clamp(1, 32);
    let (w, h) = s.size();
    let (sw, sh) = (w as u32 * scale, h as u32 * scale);
    if sw > out_w || sh > out_h {
        return std::ptr::null_mut();
    }
    let bg = [(bg_rgba >> 24) as u8, (bg_rgba >> 16) as u8, (bg_rgba >> 8) as u8];
    let mut rgba = s.composite_frame_bytes(frame as usize);
    makapix_codec::flatten_over_bg(&mut rgba, bg);
    let scaled = makapix_codec::upscale_nearest(w as u32, h as u32, &rgba, scale);
    let mut out = makapix_codec::center_pad_rgba(
        sw,
        sh,
        &scaled,
        out_w,
        out_h,
        [bg[0], bg[1], bg[2], 255],
        format == 1,
    );
    if let Some(ov) = TIMELAPSE_OVERLAY.lock().expect("overlay lock poisoned").as_ref() {
        makapix_codec::blit_rgba_over(out_w, out_h, &mut out, ov.w, ov.h, &ov.rgba, ov.x, ov.y);
    }
    match format {
        0 => bytes_out(out, out_len),
        _ => bytes_out(makapix_codec::rgba_to_i420(out_w, out_h, &out), out_len),
    }
}

enum TlEncoder {
    Gif(makapix_codec::GifStreamEncoder),
    Webp(makapix_codec::WebpAnimEncoder),
}

/// The push-mode timelapse encoder in flight (Windows WebP/GIF sink). Process-wide slot,
/// same one-export-at-a-time doctrine as the overlay and the progress atomics.
static TL_ENCODER: std::sync::Mutex<Option<TlEncoder>> = std::sync::Mutex::new(None);

/// Begin a push-mode timelapse encode at OUTPUT resolution `w`×`h` (frames arrive already
/// upscaled/padded/branded from `mkpx_timelapse_frame` format 0). `format`: 0 = GIF,
/// 1 = animated lossless WebP. Returns 0 ok, -1 on a bad format/failed init (any previous
/// unfinished encode is dropped).
#[no_mangle]
pub extern "C" fn mkpx_tl_encode_begin(format: c_int, w: u32, h: u32) -> c_int {
    let enc = match format {
        0 => match makapix_codec::GifStreamEncoder::new(w, h) {
            Ok(e) => TlEncoder::Gif(e),
            Err(_) => return -1,
        },
        1 => TlEncoder::Webp(makapix_codec::WebpAnimEncoder::new(w, h)),
        _ => return -1,
    };
    *TL_ENCODER.lock().expect("tl encoder lock poisoned") = Some(enc);
    0
}

/// Push one RGBA frame (`len` = w*h*4 of the begun encode) with its display duration.
/// Returns 0 ok, -1 on no encode in flight / length mismatch / encode error (the encode is
/// aborted on error).
#[no_mangle]
pub extern "C" fn mkpx_tl_encode_push(rgba: *const u8, len: u64, duration_ms: u32) -> c_int {
    if rgba.is_null() {
        return -1;
    }
    let src = unsafe { slice::from_raw_parts(rgba, len as usize) };
    let mut slot = TL_ENCODER.lock().expect("tl encoder lock poisoned");
    let ok = match slot.as_mut() {
        None => false,
        Some(TlEncoder::Gif(e)) => e.push(src.to_vec(), duration_ms.saturating_mul(1000)).is_ok(),
        Some(TlEncoder::Webp(e)) => e.push(src.to_vec(), duration_ms.saturating_mul(1000)).is_ok(),
    };
    if !ok {
        *slot = None; // a failed push poisons the encode; the shell aborts and reports
        return -1;
    }
    0
}

/// Finish the push-mode encode and return the container bytes (free with
/// `mkpx_free_bytes`); len via `out_len`. Null when no encode is in flight or finalization
/// fails. The slot is cleared either way.
#[no_mangle]
pub extern "C" fn mkpx_tl_encode_end(out_len: *mut u64) -> *mut u8 {
    let enc = TL_ENCODER.lock().expect("tl encoder lock poisoned").take();
    let bytes = match enc {
        None => return std::ptr::null_mut(),
        Some(TlEncoder::Gif(e)) => e.finish(),
        Some(TlEncoder::Webp(e)) => e.finish(),
    };
    match bytes {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Drop an in-flight push-mode encode (cancel/cleanup). Idempotent.
#[no_mangle]
pub extern "C" fn mkpx_tl_encode_abort() {
    *TL_ENCODER.lock().expect("tl encoder lock poisoned") = None;
}

fn bytes_out(v: Vec<u8>, out_len: *mut u64) -> *mut u8 {
    let boxed = v.into_boxed_slice();
    let len = boxed.len();
    if !out_len.is_null() {
        unsafe { *out_len = len as u64 };
    }
    Box::into_raw(boxed) as *mut u8
}

#[no_mangle]
pub extern "C" fn mkpx_free_string(p: *mut c_char) {
    if !p.is_null() {
        unsafe { drop(CString::from_raw(p)) };
    }
}

#[no_mangle]
pub extern "C" fn mkpx_free_bytes(p: *mut u8, len: u64) {
    if !p.is_null() {
        unsafe {
            let slice = slice::from_raw_parts_mut(p, len as usize);
            drop(Box::from_raw(slice as *mut [u8]));
        }
    }
}

/// Borrow a C string argument (used by helpers below) safely.
#[allow(dead_code)]
fn borrow_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

fn cstring(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_lifecycle_run_display_save_load() {
        let p = mkpx_new(16, 16);
        assert!(!p.is_null());
        let script = b"SelectTool(Pencil); SetPrimaryColor(#FFFFFFFF); Tap(5,5)";
        let err = mkpx_run(p, script.as_ptr(), script.len());
        assert!(err.is_null());
        assert_eq!(mkpx_width(p), 16);
        let mut buf = vec![0u8; 16 * 16 * 4];
        let n = mkpx_display(p, 0, 0, 0, buf.as_mut_ptr(), buf.len());
        assert_eq!(n, 16 * 16 * 4);
        let mut len: u64 = 0;
        let saved = mkpx_save(p, &mut len);
        assert!(!saved.is_null() && len > 0);
        let p2 = mkpx_new(8, 8);
        assert_eq!(mkpx_load(p2, saved, len as usize), 0);
        assert_eq!(mkpx_width(p2), 16);
        mkpx_free_bytes(saved, len);
        mkpx_free(p);
        mkpx_free(p2);
    }

    #[test]
    fn ffi_used_colors_json() {
        let p = mkpx_new(16, 16);
        let empty = mkpx_used_colors_json(p);
        assert_eq!(unsafe { std::ffi::CStr::from_ptr(empty) }.to_str().unwrap(), "{\"colors\":[]}");
        mkpx_free_string(empty);
        let script = b"SelectTool(Pencil); SetPrimaryColor(#112233FF); Tap(5,5)";
        let err = mkpx_run(p, script.as_ptr(), script.len());
        assert!(err.is_null());
        let one = mkpx_used_colors_json(p);
        assert_eq!(
            unsafe { std::ffi::CStr::from_ptr(one) }.to_str().unwrap(),
            "{\"colors\":[\"#112233FF\"]}"
        );
        mkpx_free_string(one);
        mkpx_free(p);
    }

    #[test]
    fn ffi_save_compact_then_load() {
        // Explicit/export save writes the compact (DEFLATE) envelope; mkpx_load auto-detects it.
        let p = mkpx_new(16, 16);
        let script = b"SelectTool(Pencil); Tap(5,5); Tap(9,9)";
        let _ = mkpx_run(p, script.as_ptr(), script.len());
        let mut len: u64 = 0;
        let saved = mkpx_save_compact(p, &mut len);
        assert!(!saved.is_null() && len > 0);
        let bytes = unsafe { slice::from_raw_parts(saved, len as usize) };
        assert!(makapix_codec::mkpx_compact::is_compact(bytes), "compact signature");
        let p2 = mkpx_new(8, 8);
        assert_eq!(mkpx_load(p2, saved, len as usize), 0, "load inflates compact");
        assert_eq!(mkpx_width(p2), 16);
        mkpx_free_bytes(saved, len);
        mkpx_free(p);
        mkpx_free(p2);
    }

    // Tests that run an export mutate the process-wide EXPORT_PROGRESS atomics; serialize them so
    // the progress assertions can't race another test's export (cargo runs tests on threads).
    static EXPORT_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn ffi_export_reports_progress() {
        let _guard = EXPORT_TEST_LOCK.lock().unwrap();
        let p = mkpx_new(16, 16);
        let script = b"SelectTool(Pencil); Tap(3,3); AddFrame()";
        let _ = mkpx_run(p, script.as_ptr(), script.len());
        assert_eq!(mkpx_frame_count(p), 2);
        mkpx_export_progress_reset();
        assert_eq!(mkpx_export_progress(), 0, "reset clears the pair");
        let mut len: u64 = 0;
        let out = mkpx_export_gif(p, 1, &mut len);
        assert!(!out.is_null() && len > 0);
        mkpx_free_bytes(out, len);
        // 2 frames → 2 composite steps + 2 encode steps: done == total == 4.
        assert_eq!(mkpx_export_progress(), (4u64 << 32) | 4, "export ends at done == total");
        mkpx_free(p);
    }

    #[test]
    fn ffi_export_png_upscaled() {
        let _guard = EXPORT_TEST_LOCK.lock().unwrap();
        let p = mkpx_new(16, 16);
        let script = b"SelectTool(Pencil); Tap(3,3)";
        let _ = mkpx_run(p, script.as_ptr(), script.len());
        let mut len: u64 = 0;
        let out = mkpx_export_png(p, 0, 8, &mut len);
        assert!(!out.is_null() && len > 0);
        let png = unsafe { slice::from_raw_parts(out, len as usize) }.to_vec();
        mkpx_free_bytes(out, len);
        let back = makapix_codec::decode(&png).unwrap();
        assert_eq!((back[0].w, back[0].h), (128, 128), "16×16 at 8× exports 128×128");
        mkpx_free(p);
    }

    #[test]
    fn ffi_export_still_webp() {
        let _guard = EXPORT_TEST_LOCK.lock().unwrap();
        let p = mkpx_new(16, 16);
        let script = b"SelectTool(Pencil); Tap(3,3)";
        let _ = mkpx_run(p, script.as_ptr(), script.len());
        let mut len: u64 = 0;
        let out = mkpx_export_frame_webp(p, 0, 4, &mut len);
        assert!(!out.is_null() && len > 0);
        let webp = unsafe { slice::from_raw_parts(out, len as usize) }.to_vec();
        mkpx_free_bytes(out, len);
        assert_eq!(&webp[8..12], b"WEBP");
        let back = makapix_codec::decode(&webp).unwrap();
        assert_eq!((back.len(), back[0].w, back[0].h), (1, 64, 64), "one 4×-scaled still frame");
        // The layer variant works too (single layer == the frame here).
        let out2 = mkpx_export_layer_webp(p, 0, 0, 1, &mut len);
        assert!(!out2.is_null() && len > 0);
        mkpx_free_bytes(out2, len);
        mkpx_free(p);
    }

    #[test]
    fn ffi_import_gif_then_export() {
        let _guard = EXPORT_TEST_LOCK.lock().unwrap();
        // build a 3-frame GIF via the codec, import it, export it back, and re-decode.
        let (w, h) = (16u32, 16u32);
        let frame = |r: u8, g: u8, b: u8| vec![r, g, b, 255].repeat((w * h) as usize);
        let gif = makapix_codec::encode_gif(
            w,
            h,
            &[(frame(255, 0, 0), 80_000), (frame(0, 255, 0), 80_000), (frame(0, 0, 255), 80_000)],
        )
        .unwrap();

        let p = mkpx_new(16, 16);
        let rc = mkpx_import(p, gif.as_ptr(), gif.len(), 1 /*stretch*/, 0 /*new frames*/, 0, 0, 0, 0, 0);
        assert_eq!(rc, 0);
        assert_eq!(mkpx_frame_count(p), 3);

        let mut len: u64 = 0;
        let out = mkpx_export_gif(p, 1, &mut len);
        assert!(!out.is_null() && len > 0);
        let exported = unsafe { slice::from_raw_parts(out, len as usize) }.to_vec();
        mkpx_free_bytes(out, len);
        let back = makapix_codec::decode(&exported).unwrap();
        assert_eq!(back.len(), 3);
        mkpx_free(p);
    }

    fn three_frame_gif() -> Vec<u8> {
        let (w, h) = (16u32, 16u32);
        let frame = |r: u8, g: u8, b: u8| vec![r, g, b, 255].repeat((w * h) as usize);
        makapix_codec::encode_gif(
            w,
            h,
            &[(frame(255, 0, 0), 80_000), (frame(0, 255, 0), 80_000), (frame(0, 0, 255), 80_000)],
        )
        .unwrap()
    }

    #[test]
    fn ffi_decode_blob_import_matches_direct() {
        // The split path (decode_image → import_decoded) must produce the exact document the
        // fused mkpx_import produces — .mkpx saves are byte-deterministic, so compare those.
        let gif = three_frame_gif();

        let direct = mkpx_new(16, 16);
        assert_eq!(mkpx_import(direct, gif.as_ptr(), gif.len(), 1, 0, 0, 0, 0, 0, 0), 0);

        let mut blob_len: u64 = 0;
        let blob = mkpx_decode_image(gif.as_ptr(), gif.len(), &mut blob_len, std::ptr::null_mut());
        assert!(!blob.is_null() && blob_len > 0);
        let split = mkpx_new(16, 16);
        assert_eq!(mkpx_import_decoded(split, blob, blob_len as usize, 1, 0, 0, 0, 0, 0, 0), 0);
        mkpx_free_bytes(blob, blob_len);
        assert_eq!(mkpx_frame_count(split), 3);

        let (mut la, mut lb) = (0u64, 0u64);
        let (sa, sb) = (mkpx_save(direct, &mut la), mkpx_save(split, &mut lb));
        assert!(!sa.is_null() && !sb.is_null());
        let (ba, bb) = unsafe {
            (slice::from_raw_parts(sa, la as usize), slice::from_raw_parts(sb, lb as usize))
        };
        assert_eq!(ba, bb, "split-path document must be byte-identical to the direct import");
        mkpx_free_bytes(sa, la);
        mkpx_free_bytes(sb, lb);
        mkpx_free(direct);
        mkpx_free(split);
    }

    #[test]
    fn ffi_decode_image_rejects_garbage() {
        let junk = [0u8; 64];
        let mut len: u64 = 0;
        let mut status: c_int = 0;
        assert!(mkpx_decode_image(junk.as_ptr(), junk.len(), &mut len, &mut status).is_null());
        assert_eq!(status, -1, "undecodable input reports a plain decode failure");
    }

    #[test]
    fn ffi_decode_image_reports_too_large() {
        // A 4097-wide single-frame GIF trips the codec's MAX_DIM gate: null blob, status -3 —
        // a valid-but-oversized file must be distinguishable from garbage (-1 above) so the
        // shell can say "too large" instead of "corrupt".
        let w = 4097u32;
        let gif =
            makapix_codec::encode_gif(w, 1, &[(vec![0u8; (w * 4) as usize], 100_000)]).unwrap();
        let mut len: u64 = 0;
        let mut status: c_int = 0;
        assert!(mkpx_decode_image(gif.as_ptr(), gif.len(), &mut len, &mut status).is_null());
        assert_eq!(status, -3);
        // The fused entry point reports the same condition as its own return code.
        let p = mkpx_new(16, 16);
        assert_eq!(mkpx_import(p, gif.as_ptr(), gif.len(), 1, 0, 0, 0, 0, 0, 0), -3);
        mkpx_free(p);
    }

    #[test]
    fn ffi_import_decoded_rejects_malformed_blob() {
        let gif = three_frame_gif();
        let mut blob_len: u64 = 0;
        let blob = mkpx_decode_image(gif.as_ptr(), gif.len(), &mut blob_len, std::ptr::null_mut());
        assert!(!blob.is_null());
        let p = mkpx_new(16, 16);
        // Truncated blob (header intact, pixel data cut short) must fail cleanly, no import.
        assert_eq!(mkpx_import_decoded(p, blob, blob_len as usize - 7, 1, 0, 0, 0, 0, 0, 0), -1);
        // Trailing garbage past the last frame is rejected too (strict length).
        assert_eq!(mkpx_import_decoded(p, blob, blob_len as usize, 1, 0, 0, 0, 0, 0, 0), 0);
        assert_eq!(mkpx_frame_count(p), 3);
        mkpx_free_bytes(blob, blob_len);
        mkpx_free(p);
    }

    #[test]
    fn ffi_import_refused_over_budget_returns_minus_two() {
        let gif = three_frame_gif();
        let mut blob_len: u64 = 0;
        let blob = mkpx_decode_image(gif.as_ptr(), gif.len(), &mut blob_len, std::ptr::null_mut());
        assert!(!blob.is_null());
        let p = mkpx_new(16, 16);
        let script = b"SetMemBudget(1,1)";
        let err = mkpx_run(p, script.as_ptr(), script.len());
        assert!(err.is_null());
        assert_eq!(
            mkpx_import_decoded(p, blob, blob_len as usize, 1, 0, 0, 0, 0, 0, 0),
            -2,
            "budget refusal must be distinguishable from a decode failure"
        );
        assert_eq!(mkpx_frame_count(p), 1, "refused import leaves the document unchanged");
        // The fused entry point reports the refusal the same way.
        assert_eq!(mkpx_import(p, gif.as_ptr(), gif.len(), 1, 0, 0, 0, 0, 0, 0), -2);
        mkpx_free_bytes(blob, blob_len);
        mkpx_free(p);
    }

    /// CRC-32C (tableless), duplicated from the engine's private impl so the production
    /// surface doesn't grow a test-only export.
    fn crc32c(bytes: &[u8]) -> u32 {
        let mut crc = 0xFFFF_FFFFu32;
        for &b in bytes {
            let mut c = (crc ^ b as u32) & 0xFF;
            for _ in 0..8 {
                c = if c & 1 != 0 { (c >> 1) ^ 0x82F6_3B78 } else { c >> 1 };
            }
            crc = (crc >> 8) ^ c;
        }
        crc ^ 0xFFFF_FFFF
    }

    /// Rewrite the INTG trailer's CRC (last 4 bytes; trailer is 13) after tampering the body —
    /// otherwise a tamper test exercises the CRC guard, which runs before everything else.
    fn reseal_crc(bytes: &mut [u8]) {
        let body_end = bytes.len() - 13;
        let crc = crc32c(&bytes[..body_end]).to_le_bytes();
        let n = bytes.len();
        bytes[n - 4..].copy_from_slice(&crc);
    }

    /// A plain-profile save of a 16×16 document with real content, as owned bytes.
    fn saved_plain_doc() -> Vec<u8> {
        let p = mkpx_new(16, 16);
        let script = b"SelectTool(Pencil); Tap(5,5)";
        let _ = mkpx_run(p, script.as_ptr(), script.len());
        let mut len: u64 = 0;
        let saved = mkpx_save(p, &mut len);
        assert!(!saved.is_null() && len > 0);
        let v = unsafe { slice::from_raw_parts(saved, len as usize) }.to_vec();
        mkpx_free_bytes(saved, len);
        mkpx_free(p);
        v
    }

    /// The stored content hash sits in HEAD at signature(8) + chunk header(9) + fixed fields(24).
    const HEAD_HASH_OFF: usize = 8 + 9 + 24;
    /// The HEAD format_version field is the first payload field: signature(8) + chunk header(9).
    const HEAD_VERSION_OFF: usize = 8 + 9;

    #[test]
    fn ffi_load_hash_mismatch_returns_one_and_loads() {
        let mut bytes = saved_plain_doc();
        bytes[HEAD_HASH_OFF] ^= 0xFF;
        reseal_crc(&mut bytes);
        let p = mkpx_new(8, 8);
        assert_eq!(mkpx_load(p, bytes.as_ptr(), bytes.len()), 1, "warning, not failure");
        assert_eq!(mkpx_width(p), 16, "the document was installed despite the warning");
        // The compact envelope around the same tampered plain reports the same warning.
        let compact = makapix_codec::mkpx_compact::compress(&bytes);
        let p2 = mkpx_new(8, 8);
        assert_eq!(mkpx_load(p2, compact.as_ptr(), compact.len()), 1);
        assert_eq!(mkpx_width(p2), 16);
        mkpx_free(p);
        mkpx_free(p2);
    }

    #[test]
    fn ffi_load_bad_magic_is_minus_two() {
        let junk = b"definitely not an .mkpx file, of any profile";
        let p = mkpx_new(8, 8);
        assert_eq!(mkpx_load(p, junk.as_ptr(), junk.len()), -2);
        assert_eq!(mkpx_width(p), 8, "a failed load leaves the session document unchanged");
        mkpx_free(p);
    }

    #[test]
    fn ffi_load_newer_version_is_minus_three() {
        let mut bytes = saved_plain_doc();
        bytes[HEAD_VERSION_OFF..HEAD_VERSION_OFF + 2].copy_from_slice(&11u16.to_le_bytes());
        reseal_crc(&mut bytes);
        let p = mkpx_new(8, 8);
        assert_eq!(mkpx_load(p, bytes.as_ptr(), bytes.len()), -3);
        assert_eq!(mkpx_width(p), 8);
        mkpx_free(p);
    }

    #[test]
    fn ffi_load_corrupt_is_minus_four() {
        let bytes = saved_plain_doc();
        let p = mkpx_new(8, 8);
        // Truncated plain container (INTG trailer gone).
        assert_eq!(mkpx_load(p, bytes.as_ptr(), bytes.len() / 2), -4);
        // Compact envelope with a corrupted DEFLATE tail.
        let mut compact = makapix_codec::mkpx_compact::compress(&bytes);
        let last = compact.len() - 1;
        compact[last] ^= 0xFF;
        assert_eq!(mkpx_load(p, compact.as_ptr(), compact.len()), -4);
        assert_eq!(mkpx_width(p), 8);
        mkpx_free(p);
    }

    #[test]
    fn ffi_load_over_budget_is_minus_five() {
        let bytes = saved_plain_doc();
        let p = mkpx_new(16, 16);
        let script = b"SetMemBudget(1,1)";
        let err = mkpx_run(p, script.as_ptr(), script.len());
        assert!(err.is_null());
        assert_eq!(
            mkpx_load(p, bytes.as_ptr(), bytes.len()),
            -5,
            "budget refusal must be distinguishable from corruption"
        );
        mkpx_free(p);
    }

    // ---- replay checkpoints + timelapse frame path ----

    fn run_ok(p: *mut Session, script: &str) {
        let err = mkpx_run(p, script.as_ptr(), script.len());
        assert!(err.is_null(), "script failed");
    }

    fn doc_hash_string(p: *mut Session) -> String {
        let c = mkpx_doc_hash(p);
        assert!(!c.is_null());
        let s = unsafe { CStr::from_ptr(c) }.to_str().unwrap().to_string();
        mkpx_free_string(c);
        s
    }

    #[test]
    fn ffi_checkpoint_lifecycle() {
        let p = mkpx_new(32, 32);
        run_ok(p, "SelectTool(Pencil); SetPrimaryColor(#D04648FF)\nStroke([(2,2),(20,20)])");
        let id = mkpx_checkpoint_take(p);
        assert!(id >= 0);
        run_ok(p, "Stroke([(4,18),(28,6)])\nAddLayer()\nStroke([(1,1),(5,5)])");
        let after = doc_hash_string(p);
        assert_eq!(mkpx_checkpoint_restore(p, id as u32), 0);
        run_ok(p, "Stroke([(4,18),(28,6)])\nAddLayer()\nStroke([(1,1),(5,5)])");
        assert_eq!(doc_hash_string(p), after, "restore + replay must equal straight run");
        // ids roundtrip + bogus restore + mid-gesture refusal.
        let mut ids = [0u32; 512];
        let n = mkpx_checkpoint_ids(p, ids.as_mut_ptr(), 512);
        assert_eq!(n, mkpx_checkpoint_count(p));
        assert!(n >= 1 && ids[..n as usize].contains(&(id as u32)));
        assert_eq!(mkpx_checkpoint_restore(p, 9999), -1);
        run_ok(p, "PointerDown(3,3)");
        assert_eq!(mkpx_checkpoint_take(p), -1, "mid-stroke take must refuse");
        run_ok(p, "PointerUp()");
        mkpx_checkpoint_clear(p);
        assert_eq!(mkpx_checkpoint_count(p), 0);
        assert_eq!(mkpx_checkpoint_restore(p, id as u32), -1);
        mkpx_free(p);
        // Null-session paths.
        assert_eq!(mkpx_checkpoint_take(std::ptr::null_mut()), -1);
        assert_eq!(mkpx_checkpoint_count(std::ptr::null_mut()), 0);
        assert!(mkpx_doc_hash(std::ptr::null_mut()).is_null());
    }

    #[test]
    fn ffi_timelapse_frame_rgba_exact() {
        // 2×2 known pixels, scale 2, padded onto 8×8 over an opaque background.
        let p = mkpx_new(2, 2);
        run_ok(p, "SelectTool(Pencil); SetBrushSize(1); SetPrimaryColor(#FF0000FF)\nTap(0,0)");
        let mut len = 0u64;
        let buf = mkpx_timelapse_frame(p, 0, 2, 8, 8, 0x102030FF, 0, &mut len);
        assert!(!buf.is_null());
        assert_eq!(len, 8 * 8 * 4);
        let px = unsafe { slice::from_raw_parts(buf, len as usize) };
        // Content (4×4) centered at (2,2): the red pixel's 2×2 block at (2,2)..(3,3).
        let at = |x: usize, y: usize| &px[(y * 8 + x) * 4..(y * 8 + x) * 4 + 4];
        assert_eq!(at(2, 2), &[255, 0, 0, 255]);
        assert_eq!(at(3, 3), &[255, 0, 0, 255]);
        // Transparent canvas pixels flatten to the background; padding is the background.
        assert_eq!(at(4, 4), &[0x10, 0x20, 0x30, 255], "transparent canvas → bg");
        assert_eq!(at(0, 0), &[0x10, 0x20, 0x30, 255], "padding → bg");
        mkpx_free_bytes(buf, len);
        // Guards: scaled size exceeding the canvas, odd I420 dims, unknown format.
        assert!(mkpx_timelapse_frame(p, 0, 8, 8, 8, 0, 0, &mut len).is_null());
        assert!(mkpx_timelapse_frame(p, 0, 1, 7, 8, 0, 1, &mut len).is_null());
        assert!(mkpx_timelapse_frame(p, 0, 1, 8, 8, 0, 2, &mut len).is_null());
        mkpx_free(p);
    }

    #[test]
    fn ffi_timelapse_frame_i420_shape() {
        let p = mkpx_new(2, 2);
        // All-black canvas (fill with an opaque black stroke covering both tiles' pixels).
        run_ok(p, "SelectTool(Pencil); SetBrushSize(4); SetPrimaryColor(#000000FF)\nStroke([(0,0),(1,1)])");
        let mut len = 0u64;
        let buf = mkpx_timelapse_frame(p, 0, 1, 8, 8, 0x000000FF, 1, &mut len);
        assert!(!buf.is_null());
        assert_eq!(len, 8 * 8 * 3 / 2, "I420 = w*h*3/2");
        let px = unsafe { slice::from_raw_parts(buf, len as usize) };
        assert!(px[..64].iter().all(|&y| y == 16), "black frame → Y=16 everywhere");
        assert!(px[64..].iter().all(|&c| c == 128), "black frame → neutral chroma");
        mkpx_free_bytes(buf, len);
        mkpx_free(p);
    }

    #[test]
    fn ffi_timelapse_overlay_blits_and_clears() {
        let p = mkpx_new(2, 2);
        let mut len = 0u64;
        // A 1×1 opaque white overlay at (0,0).
        let ov = [255u8, 255, 255, 255];
        assert_eq!(mkpx_timelapse_set_overlay(ov.as_ptr(), 1, 1, 0, 0), 0);
        let buf = mkpx_timelapse_frame(p, 0, 1, 4, 4, 0x000000FF, 0, &mut len);
        let px = unsafe { slice::from_raw_parts(buf, len as usize) };
        assert_eq!(&px[0..4], &[255, 255, 255, 255], "overlay blitted at (0,0)");
        mkpx_free_bytes(buf, len);
        // Clear → gone.
        assert_eq!(mkpx_timelapse_set_overlay(std::ptr::null(), 0, 0, 0, 0), 0);
        let buf = mkpx_timelapse_frame(p, 0, 1, 4, 4, 0x000000FF, 0, &mut len);
        let px = unsafe { slice::from_raw_parts(buf, len as usize) };
        assert_eq!(&px[0..4], &[0, 0, 0, 255], "cleared overlay no longer draws");
        mkpx_free_bytes(buf, len);
        // Oversize refused.
        assert_eq!(mkpx_timelapse_set_overlay(ov.as_ptr(), 4096, 1, 0, 0), -1);
        mkpx_free(p);
    }

    #[test]
    fn ffi_tl_encode_push_mode_roundtrip() {
        let _guard = EXPORT_TEST_LOCK.lock().unwrap(); // shares the process-wide encoder slot
        let f0 = vec![255u8, 0, 0, 255].repeat(16); // 4×4 red
        let mut f1 = f0.clone();
        f1[0..4].copy_from_slice(&[0, 255, 0, 255]);
        // GIF.
        assert_eq!(mkpx_tl_encode_begin(0, 4, 4), 0);
        assert_eq!(mkpx_tl_encode_push(f0.as_ptr(), f0.len() as u64, 100), 0);
        assert_eq!(mkpx_tl_encode_push(f1.as_ptr(), f1.len() as u64, 50), 0);
        let mut len = 0u64;
        let buf = mkpx_tl_encode_end(&mut len);
        assert!(!buf.is_null() && len > 0);
        let gif = unsafe { slice::from_raw_parts(buf, len as usize) }.to_vec();
        assert_eq!(&gif[0..3], b"GIF");
        mkpx_free_bytes(buf, len);
        // WebP.
        assert_eq!(mkpx_tl_encode_begin(1, 4, 4), 0);
        assert_eq!(mkpx_tl_encode_push(f0.as_ptr(), f0.len() as u64, 100), 0);
        assert_eq!(mkpx_tl_encode_push(f1.as_ptr(), f1.len() as u64, 50), 0);
        let buf = mkpx_tl_encode_end(&mut len);
        assert!(!buf.is_null());
        let webp = unsafe { slice::from_raw_parts(buf, len as usize) };
        assert_eq!(&webp[0..4], b"RIFF");
        assert_eq!(&webp[8..12], b"WEBP");
        mkpx_free_bytes(buf, len);
        // End with nothing in flight → null; abort is idempotent; bad begin format refused.
        assert!(mkpx_tl_encode_end(&mut len).is_null());
        mkpx_tl_encode_abort();
        mkpx_tl_encode_abort();
        assert_eq!(mkpx_tl_encode_begin(7, 4, 4), -1);
        // A wrong-length push aborts the encode.
        assert_eq!(mkpx_tl_encode_begin(1, 4, 4), 0);
        assert_eq!(mkpx_tl_encode_push(f0.as_ptr(), 5, 100), -1);
        assert!(mkpx_tl_encode_end(&mut len).is_null(), "failed push poisons the encode");
    }
}
