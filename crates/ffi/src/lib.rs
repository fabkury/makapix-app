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

/// Load a `.mkpx` document from bytes — accepts both the **plain** container and the **compact**
/// (DEFLATE) envelope, auto-detected by signature. Returns 0 on success, -1 on failure.
#[no_mangle]
pub extern "C" fn mkpx_load(ptr: *mut Session, data: *const u8, len: usize) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    if makapix_codec::mkpx_compact::is_compact(bytes) {
        // Inflate the compact envelope at the periphery, then load the plain bytes in the engine.
        match makapix_codec::mkpx_compact::open(bytes) {
            Ok(plain) => match s.load_bytes(&plain) {
                Ok(()) => 0,
                Err(_) => -1,
            },
            Err(_) => -1,
        }
    } else {
        // Plain container — load directly, no copy.
        match s.load_bytes(bytes) {
            Ok(()) => 0,
            Err(_) => -1,
        }
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

/// Import an image file (GIF/PNG/APNG/JPEG/BMP/WebP) into the document.
/// `mode`: 0=Fit, 1=Stretch, 2=Crop. `as_layer`: 0/1. A non-empty crop rect (`crop_w>0 && crop_h>0`,
/// source pixels) places that region 1:1 centered on the canvas (downscaled to fit only when larger,
/// never upscaled), overriding `mode`. Returns 0 on success, -1 on failure.
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
        Err(_) => return -1,
    };
    use makapix_engine::geom::IRect;
    use makapix_engine::import::{Anchor, ImportConfig, ScaleMode};
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
    s.import_decoded(&frames, cfg);
    0
}

/// Upscale (nearest-neighbour) then encode one frame's RGBA as PNG or lossless WebP, with coarse
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

/// Export the active (or given) frame as PNG, upscaled ×`scale` (nearest-neighbour, clamped
/// 1..=32). Returns a malloc'd buffer; len via `out_len`.
#[no_mangle]
pub extern "C" fn mkpx_export_png(ptr: *mut Session, frame: u32, scale: u32, out_len: *mut u64) -> *mut u8 {
    export_frame_still(ptr, frame, scale, false, out_len)
}

/// Export the active (or given) frame as a LOSSLESS static WebP, upscaled ×`scale` — the still
/// twin of `mkpx_export_png` (for artwork whose colours exceed formats like GIF; distinct from
/// `mkpx_export_webp`, which exports the whole animation).
#[no_mangle]
pub extern "C" fn mkpx_export_frame_webp(ptr: *mut Session, frame: u32, scale: u32, out_len: *mut u64) -> *mut u8 {
    export_frame_still(ptr, frame, scale, true, out_len)
}

/// Export ONE layer of one frame as a PNG — the layer's own pixels (straight alpha), not the
/// composite — upscaled ×`scale` (nearest-neighbour, clamped 1..=32). Stale indices clamp
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

/// Composite every frame with per-frame progress (steps 0..n of 2n) and honouring cancel.
/// Returns `None` when cancelled mid-way.
fn composite_frames_tracked(s: &mut Session) -> Option<Vec<(Vec<u8>, u32)>> {
    let n = s.doc.frames.len();
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    export_progress_set(0, 2 * n as u32);
    let mut frames: Vec<(Vec<u8>, u32)> = Vec::with_capacity(n);
    for i in 0..n {
        if EXPORT_CANCEL.load(Ordering::Relaxed) {
            return None;
        }
        frames.push((s.composite_frame_bytes(i), s.doc.frames[i].duration_us));
        export_progress_set(i as u32 + 1, 2 * n as u32);
    }
    Some(frames)
}

/// The encoders' per-frame hook: steps n..2n of 2n, and `false` (= abort) once cancel is set.
fn encode_progress_hook(done: usize, total: usize) -> bool {
    export_progress_set((total + done) as u32, 2 * total as u32);
    !EXPORT_CANCEL.load(Ordering::Relaxed)
}

/// Export all frames as an animated GIF, upscaled ×`scale` (nearest-neighbour, clamped 1..=32,
/// applied one frame at a time). Returns a malloc'd buffer; len via `out_len`. Progress is
/// reported via `mkpx_export_progress`; null on failure OR `mkpx_export_cancel`.
#[no_mangle]
pub extern "C" fn mkpx_export_gif(ptr: *mut Session, scale: u32, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    let frames = match composite_frames_tracked(s) {
        Some(f) => f,
        None => return std::ptr::null_mut(),
    };
    match makapix_codec::encode_gif_with(w as u32, h as u32, &frames, scale, &mut encode_progress_hook) {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Export the artwork as a LOSSLESS WebP (static for one frame, animated WebP for many) — the
/// recommended format for Makapix Club submissions — upscaled ×`scale` (nearest-neighbour,
/// clamped 1..=32, applied one frame at a time). Returns a malloc'd buffer; len via `out_len`.
/// Progress is reported via `mkpx_export_progress`; null on failure OR `mkpx_export_cancel`.
#[no_mangle]
pub extern "C" fn mkpx_export_webp(ptr: *mut Session, scale: u32, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    let frames = match composite_frames_tracked(s) {
        Some(f) => f,
        None => return std::ptr::null_mut(),
    };
    match makapix_codec::encode_animated_webp_with(w as u32, h as u32, &frames, scale, &mut encode_progress_hook) {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
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
}
