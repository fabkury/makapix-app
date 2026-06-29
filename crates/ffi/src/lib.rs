//! C ABI bridge (SPEC §19). A `Session` lives behind an opaque pointer; the Flutter shell
//! drives it with DSL command strings and pulls composited RGBA bytes for display. No
//! panics cross the boundary (errors are returned as strings / status codes).

// Every `extern "C"` export here necessarily dereferences raw pointers handed across the C ABI
// from Dart; that is the whole point of this crate. Marking each `unsafe` would not change the
// C ABI and only adds noise, so we allow the lint crate-wide (the contract is documented per fn).
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use makapix_engine::Session;
use std::ffi::{c_char, CStr, CString};
use std::os::raw::c_int;
use std::slice;

/// Create a new session with a `w×h` document. Returns an opaque pointer (null on bad args).
#[no_mangle]
pub extern "C" fn mkpx_new(w: u16, h: u16) -> *mut Session {
    if !(8..=256).contains(&w) || !(8..=256).contains(&h) {
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

/// Load a `.mkpx` document from bytes. Returns 0 on success, -1 on failure.
#[no_mangle]
pub extern "C" fn mkpx_load(ptr: *mut Session, data: *const u8, len: usize) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    match s.load_bytes(bytes) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Import an image file (GIF/PNG/APNG/JPEG/BMP/WebP) into the document.
/// `mode`: 0=Fit, 1=Stretch, 2=Crop. `as_layer`: 0/1. Returns 0 on success, -1 on failure.
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

/// Export the active (or given) frame as PNG. Returns a malloc'd buffer; len via `out_len`.
#[no_mangle]
pub extern "C" fn mkpx_export_png(ptr: *mut Session, frame: u32, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    let rgba = s.composite_frame_bytes(frame as usize);
    match makapix_codec::encode_png(w as u32, h as u32, &rgba) {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Export all frames as an animated GIF. Returns a malloc'd buffer; len via `out_len`.
#[no_mangle]
pub extern "C" fn mkpx_export_gif(ptr: *mut Session, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    let frames: Vec<(Vec<u8>, u32)> = s
        .doc
        .frames
        .iter()
        .enumerate()
        .map(|(i, f)| (s.composite_frame_bytes(i), f.duration_us))
        .collect();
    match makapix_codec::encode_gif(w as u32, h as u32, &frames) {
        Ok(v) => bytes_out(v, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Export the artwork as a LOSSLESS WebP (static for one frame, animated WebP for many) — the
/// recommended format for Makapix Club submissions. Returns a malloc'd buffer; len via `out_len`.
#[no_mangle]
pub extern "C" fn mkpx_export_webp(ptr: *mut Session, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    let (w, h) = s.size();
    let frames: Vec<(Vec<u8>, u32)> = s
        .doc
        .frames
        .iter()
        .enumerate()
        .map(|(i, f)| (s.composite_frame_bytes(i), f.duration_us))
        .collect();
    match makapix_codec::encode_animated_webp(w as u32, h as u32, &frames) {
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
    fn ffi_import_gif_then_export() {
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
        let out = mkpx_export_gif(p, &mut len);
        assert!(!out.is_null() && len > 0);
        let exported = unsafe { slice::from_raw_parts(out, len as usize) }.to_vec();
        mkpx_free_bytes(out, len);
        let back = makapix_codec::decode(&exported).unwrap();
        assert_eq!(back.len(), 3);
        mkpx_free(p);
    }
}
