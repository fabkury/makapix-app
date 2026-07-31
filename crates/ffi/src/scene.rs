//! The Animator's C ABI — the `mkps_*` family over `SceneSession`, in the SAME cdylib as the
//! `mkpx_*` editor family (one library, one allocator; freed with the existing
//! `mkpx_free_string` / `mkpx_free_bytes`; export progress/cancel ride the existing
//! process-wide `mkpx_export_progress` atomics — total = 2·frames, one step per composite and
//! one per encoded frame). Conventions inherited verbatim: opaque `Box::into_raw` pointers,
//! null-guarded reborrow helper, capacity checked before any copy, sentinel returns, and
//! never panicking (panic = "abort" makes unwinding impossible; safety = not panicking).

use crate::{bytes_out, cstring, export_progress_set, EXPORT_CANCEL};
use makapix_scene::model::{SceneFps, MAX_PROP_FRAMES, PROP_IMPORT_MAX_BYTES};
use makapix_scene::SceneSession;
use std::ffi::c_char;
use std::os::raw::c_int;
use std::slice;
use std::sync::atomic::{AtomicBool, Ordering};

/// 1 iff the most recent `mkps_export_gif` thresholded any semi-transparent pixel — the
/// decided "GIF flattened your fades" notice signal. Process-wide like the progress atomics
/// (polled from the UI isolate while the export runs elsewhere); reset at each GIF export.
static EXPORT_ALPHA_LOSSY: AtomicBool = AtomicBool::new(false);

fn session<'a>(ptr: *mut SceneSession) -> Option<&'a mut SceneSession> {
    if ptr.is_null() {
        None
    } else {
        Some(unsafe { &mut *ptr })
    }
}

fn json_esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

// ---- lifecycle / command ---------------------------------------------------------------------

/// New session. Null on an unknown frame rate (dimensions clamp like the DSL).
#[no_mangle]
pub extern "C" fn mkps_new(w: u16, h: u16, millifps: u32) -> *mut SceneSession {
    match SceneFps::from_millifps(millifps) {
        Some(fps) => Box::into_raw(Box::new(SceneSession::new(w, h, fps))),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn mkps_free(ptr: *mut SceneSession) {
    if !ptr.is_null() {
        drop(unsafe { Box::from_raw(ptr) });
    }
}

/// Run a DSL script. Null = success; otherwise a malloc'd error C string
/// (free with `mkpx_free_string`).
#[no_mangle]
pub extern "C" fn mkps_run(ptr: *mut SceneSession, script: *const u8, len: usize) -> *mut c_char {
    let s = match session(ptr) {
        Some(s) => s,
        None => return cstring("null session"),
    };
    if script.is_null() {
        return cstring("null script");
    }
    let bytes = unsafe { slice::from_raw_parts(script, len) };
    let src = match std::str::from_utf8(bytes) {
        Ok(v) => v,
        Err(_) => return cstring("script is not valid UTF-8"),
    };
    match s.run_script(src) {
        Ok(()) => std::ptr::null_mut(),
        Err(e) => cstring(&e),
    }
}

// ---- state -----------------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn mkps_state_json(ptr: *mut SceneSession) -> *mut c_char {
    match session(ptr) {
        Some(s) => cstring(&s.state_json()),
        None => cstring("{}"),
    }
}

#[no_mangle]
pub extern "C" fn mkps_mem_json(ptr: *mut SceneSession) -> *mut c_char {
    match session(ptr) {
        Some(s) => cstring(&s.mem_json()),
        None => cstring("{}"),
    }
}

#[no_mangle]
pub extern "C" fn mkps_width(ptr: *mut SceneSession) -> u32 {
    session(ptr).map_or(0, |s| s.size().0 as u32)
}

#[no_mangle]
pub extern "C" fn mkps_height(ptr: *mut SceneSession) -> u32 {
    session(ptr).map_or(0, |s| s.size().1 as u32)
}

#[no_mangle]
pub extern "C" fn mkps_frame_count(ptr: *mut SceneSession) -> u32 {
    session(ptr).map_or(0, |s| s.frame_count())
}

#[no_mangle]
pub extern "C" fn mkps_playhead(ptr: *mut SceneSession) -> u32 {
    session(ptr).map_or(0, |s| s.playhead)
}

#[no_mangle]
pub extern "C" fn mkps_play_frame(ptr: *mut SceneSession) -> u32 {
    session(ptr).map_or(0, |s| s.current_play_frame())
}

#[no_mangle]
pub extern "C" fn mkps_cache_epoch(ptr: *mut SceneSession) -> u64 {
    session(ptr).map_or(0, |s| s.cache_epoch())
}

// ---- pixels (caller-provides-buffer; STRAIGHT alpha — Dart premultiplies) --------------------

#[no_mangle]
pub extern "C" fn mkps_composite(
    ptr: *mut SceneSession,
    frame: u32,
    out: *mut u8,
    cap: usize,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.composite_bytes(frame.min(s.frame_count().saturating_sub(1)));
    if out.is_null() || bytes.len() > cap {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()) }.copy_from_slice(&bytes);
    bytes.len() as c_int
}

#[no_mangle]
pub extern "C" fn mkps_frame_hash(ptr: *mut SceneSession, frame: u32) -> u64 {
    session(ptr).map_or(0, |s| s.frame_hash(frame.min(s.frame_count().saturating_sub(1))))
}

#[no_mangle]
pub extern "C" fn mkps_prop_thumb(
    ptr: *mut SceneSession,
    prop: u32,
    tw: u32,
    th: u32,
    out: *mut u8,
    cap: usize,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.prop_thumb_bytes(prop, tw, th);
    if bytes.is_empty() || out.is_null() || bytes.len() > cap {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()) }.copy_from_slice(&bytes);
    bytes.len() as c_int
}

#[no_mangle]
pub extern "C" fn mkps_actor_thumb(
    ptr: *mut SceneSession,
    actor: u32,
    tw: u32,
    th: u32,
    out: *mut u8,
    cap: usize,
) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    let bytes = s.actor_thumb_bytes(actor, tw, th);
    if bytes.is_empty() || out.is_null() || bytes.len() > cap {
        return -1;
    }
    unsafe { slice::from_raw_parts_mut(out, bytes.len()) }.copy_from_slice(&bytes);
    bytes.len() as c_int
}

/// Topmost visible Actor whose transformed opaque pixel covers scene point (x, y) at `frame`,
/// else -1.
#[no_mangle]
pub extern "C" fn mkps_hit_test(ptr: *mut SceneSession, frame: u32, x: i32, y: i32) -> i32 {
    match session(ptr) {
        Some(s) => s.hit_test(frame, x, y).map_or(-1, |id| id as i32),
        None => -1,
    }
}

// ---- documents -------------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn mkps_save(ptr: *mut SceneSession, out_len: *mut u64) -> *mut u8 {
    match session(ptr) {
        Some(s) => bytes_out(s.save_bytes(), out_len),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn mkps_save_compact(ptr: *mut SceneSession, out_len: *mut u64) -> *mut u8 {
    match session(ptr) {
        Some(s) => bytes_out(s.save_bytes_compact(), out_len),
        None => std::ptr::null_mut(),
    }
}

/// 0 = ok, -1 = failure (bad bytes / over budget). Plain or compact by signature.
#[no_mangle]
pub extern "C" fn mkps_load(ptr: *mut SceneSession, data: *const u8, len: usize) -> c_int {
    let s = match session(ptr) {
        Some(s) => s,
        None => return -1,
    };
    if data.is_null() {
        return -1;
    }
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    match s.load_bytes(bytes) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

// ---- import ----------------------------------------------------------------------------------

/// SESSION-FREE probe of importable bytes, for the Whole/Parts card BEFORE anything is
/// imported. JSON: `{"kind":"mkpx","w":..,"h":..,"frames":..,"layers":[{"name":".."},..]}` or
/// `{"kind":"raster","w":..,"h":..,"frames":..}` or `{"error":"unsupported"|"too_large"}`.
/// Free with `mkpx_free_string`.
#[no_mangle]
pub extern "C" fn mkps_probe_import(data: *const u8, len: usize) -> *mut c_char {
    if data.is_null() {
        return cstring("{\"error\":\"unsupported\"}");
    }
    let bytes = unsafe { slice::from_raw_parts(data, len) };

    // `.mkpx`, plain or compact.
    let plain: Option<Vec<u8>> = if makapix_codec::mkpx_compact::is_compact(bytes) {
        makapix_codec::mkpx_compact::open(bytes).ok()
    } else if bytes.len() >= 8 && bytes[..8] == makapix_engine::io::SIGNATURE {
        Some(bytes.to_vec())
    } else {
        None
    };
    if let Some(plain) = plain {
        return match makapix_engine::io::load_from_bytes_budgeted(&plain, PROP_IMPORT_MAX_BYTES) {
            Ok(doc) => {
                let rect = doc.canvas_rect();
                let layers: Vec<String> = doc.frames[0]
                    .layers
                    .iter()
                    .map(|l| format!("{{\"name\":\"{}\"}}", json_esc(&l.name)))
                    .collect();
                cstring(&format!(
                    "{{\"kind\":\"mkpx\",\"w\":{},\"h\":{},\"frames\":{},\"layers\":[{}]}}",
                    rect.w,
                    rect.h,
                    doc.frames.len(),
                    layers.join(",")
                ))
            }
            Err(makapix_engine::io::IoError::TooLarge(_)) => cstring("{\"error\":\"too_large\"}"),
            Err(_) => cstring("{\"error\":\"unsupported\"}"),
        };
    }

    match makapix_codec::decode_with_limits(bytes, MAX_PROP_FRAMES, PROP_IMPORT_MAX_BYTES) {
        Ok(frames) => cstring(&format!(
            "{{\"kind\":\"raster\",\"w\":{},\"h\":{},\"frames\":{}}}",
            frames[0].w,
            frames[0].h,
            frames.len()
        )),
        Err(makapix_codec::CodecError::Decode(e))
            if e.contains("too large") || e.contains("too many") =>
        {
            cstring("{\"error\":\"too_large\"}")
        }
        Err(_) => cstring("{\"error\":\"unsupported\"}"),
    }
}

/// Import bytes as Prop(s) (the scene-side chokepoint: budget-refused imports leave the Scene
/// untouched). `split_layers` splits a multi-layer `.mkpx` into one Prop per layer;
/// `place_actors` places one Actor per new Prop (split parts self-assemble). Result JSON:
/// `{"props":[{"id":..,"name":"..","w":..,"h":..,"frames":..}],"actors":[..]}` or
/// `{"error":".."}`. Free with `mkpx_free_string`.
#[no_mangle]
pub extern "C" fn mkps_import_prop(
    ptr: *mut SceneSession,
    data: *const u8,
    len: usize,
    split_layers: c_int,
    place_actors: c_int,
    name: *const c_char,
) -> *mut c_char {
    let s = match session(ptr) {
        Some(s) => s,
        None => return cstring("{\"error\":\"null session\"}"),
    };
    if data.is_null() {
        return cstring("{\"error\":\"null data\"}");
    }
    let bytes = unsafe { slice::from_raw_parts(data, len) };
    let name = if name.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(name) }.to_string_lossy().into_owned()
    };
    match s.import_prop_bytes(bytes, &name, split_layers != 0, place_actors != 0) {
        Ok(outcome) => {
            let props: Vec<String> = outcome
                .props
                .iter()
                .filter_map(|&id| s.scene.prop(id))
                .map(|p| {
                    format!(
                        "{{\"id\":{},\"name\":\"{}\",\"w\":{},\"h\":{},\"frames\":{}}}",
                        p.id,
                        json_esc(&p.name),
                        p.w,
                        p.h,
                        p.frames.len()
                    )
                })
                .collect();
            let actors: Vec<String> = outcome.actors.iter().map(|a| a.to_string()).collect();
            cstring(&format!(
                "{{\"props\":[{}],\"actors\":[{}]}}",
                props.join(","),
                actors.join(",")
            ))
        }
        Err(e) => cstring(&format!("{{\"error\":\"{}\"}}", json_esc(&e))),
    }
}

// ---- export (shared process-wide progress atomics; total = 2·frames) -------------------------

#[no_mangle]
pub extern "C" fn mkps_export_gif(ptr: *mut SceneSession, scale: u32, out_len: *mut u64) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    EXPORT_ALPHA_LOSSY.store(false, Ordering::Relaxed);
    let n = s.frame_count();
    export_progress_set(0, 2 * n);
    let hook = |_done: usize, _total: usize| -> bool {
        crate::export_progress_inc();
        !EXPORT_CANCEL.load(Ordering::Relaxed)
    };
    // The composite half of the progress is stepped inside export_gif's frame closure via the
    // encoder's per-frame callback cadence (compose+encode alternate 1:1), so the packed
    // counter still ends at (2n<<32|2n): step once per composite here.
    let s_ref: &SceneSession = s;
    let result = {
        let mut composed = 0u32;
        let mut wrapped = |done: usize, total: usize| -> bool {
            if composed < n {
                composed += 1;
                crate::export_progress_inc(); // the composite step
            }
            hook(done, total)
        };
        s_ref.export_gif(scale.max(1), &mut wrapped)
    };
    match result {
        Ok((bytes, lossy)) => {
            EXPORT_ALPHA_LOSSY.store(lossy, Ordering::Relaxed);
            bytes_out(bytes, out_len)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn mkps_export_webp(
    ptr: *mut SceneSession,
    scale: u32,
    out_len: *mut u64,
) -> *mut u8 {
    let s = match session(ptr) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };
    EXPORT_CANCEL.store(false, Ordering::Relaxed);
    let n = s.frame_count();
    export_progress_set(0, 2 * n);
    let s_ref: &SceneSession = s;
    let result = {
        let mut composed = 0u32;
        let mut wrapped = |_done: usize, _total: usize| -> bool {
            if composed < n {
                composed += 1;
                crate::export_progress_inc();
            }
            crate::export_progress_inc();
            !EXPORT_CANCEL.load(Ordering::Relaxed)
        };
        s_ref.export_webp(scale.max(1), &mut wrapped)
    };
    match result {
        Ok(bytes) => bytes_out(bytes, out_len),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 1 iff the most recent `mkps_export_gif` thresholded semi-transparent pixels.
#[no_mangle]
pub extern "C" fn mkps_export_alpha_lossy() -> u32 {
    EXPORT_ALPHA_LOSSY.load(Ordering::Relaxed) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(s: *mut SceneSession, script: &str) {
        let e = mkps_run(s, script.as_ptr(), script.len());
        assert!(e.is_null(), "script failed");
    }

    #[test]
    fn lifecycle_composite_save_load_roundtrip() {
        let s = mkps_new(24, 16, 12_500);
        assert!(!s.is_null());
        run(s, "GenPropSolid(6,6,#FF8040FF); PlaceActorAt(1, 8, 8); SetKey(1, x, 0, 4); SetKey(1, x, 10, 20)");
        assert_eq!(mkps_width(s), 24);
        assert_eq!(mkps_frame_count(s), 25);

        let mut buf = vec![0u8; 24 * 16 * 4];
        let n = mkps_composite(s, 5, buf.as_mut_ptr(), buf.len());
        assert_eq!(n, (24 * 16 * 4) as c_int);
        assert!(buf.chunks_exact(4).any(|px| px[3] != 0), "something rendered");

        let h5 = mkps_frame_hash(s, 5);
        let mut len = 0u64;
        let p = mkps_save(s, &mut len);
        assert!(!p.is_null() && len > 0);
        let bytes = unsafe { slice::from_raw_parts(p, len as usize) }.to_vec();
        crate::mkpx_free_bytes(p, len);

        let s2 = mkps_new(8, 8, 25_000);
        assert_eq!(mkps_load(s2, bytes.as_ptr(), bytes.len()), 0);
        assert_eq!(mkps_width(s2), 24);
        assert_eq!(mkps_frame_hash(s2, 5), h5, "composites identical after round-trip");
        mkps_free(s2);
        mkps_free(s);
    }

    #[test]
    fn null_guards_never_crash() {
        let null = std::ptr::null_mut();
        assert_eq!(mkps_width(null), 0);
        assert_eq!(mkps_frame_hash(null, 0), 0);
        assert_eq!(mkps_composite(null, 0, std::ptr::null_mut(), 0), -1);
        assert_eq!(mkps_load(null, std::ptr::null(), 0), -1);
        assert!(mkps_export_gif(null, 1, std::ptr::null_mut()).is_null());
        assert!(mkps_new(16, 16, 30_000).is_null(), "bad fps → null");
        mkps_free(null); // no-op
        let e = mkps_run(null, b"x".as_ptr(), 1);
        assert!(!e.is_null());
        crate::mkpx_free_string(e);
    }

    #[test]
    fn run_reports_parse_errors() {
        let s = mkps_new(16, 16, 12_500);
        let bad = "Nonsense(1)";
        let e = mkps_run(s, bad.as_ptr(), bad.len());
        assert!(!e.is_null());
        crate::mkpx_free_string(e);
        mkps_free(s);
    }

    #[test]
    fn probe_and_import_json_contracts() {
        // Raster probe via an in-memory PNG.
        let rgba = vec![1u8, 2, 3, 255].repeat(9);
        let png = makapix_codec::encode_png(3, 3, &rgba).unwrap();
        let p = mkps_probe_import(png.as_ptr(), png.len());
        let j = unsafe { std::ffi::CStr::from_ptr(p) }.to_string_lossy().into_owned();
        crate::mkpx_free_string(p);
        assert!(j.contains("\"kind\":\"raster\"") && j.contains("\"w\":3"), "{j}");

        // .mkpx probe reports layers.
        let mut doc = makapix_engine::Document::new(9, 7);
        let top = doc.new_layer("arm");
        doc.active_frame_mut().layers.push(top);
        let mk = makapix_engine::io::save_to_bytes(&doc);
        let p2 = mkps_probe_import(mk.as_ptr(), mk.len());
        let j2 = unsafe { std::ffi::CStr::from_ptr(p2) }.to_string_lossy().into_owned();
        crate::mkpx_free_string(p2);
        assert!(j2.contains("\"kind\":\"mkpx\"") && j2.contains("\"name\":\"arm\""), "{j2}");

        // Import into a session.
        let s = mkps_new(16, 16, 12_500);
        let r = mkps_import_prop(s, png.as_ptr(), png.len(), 0, 1, std::ptr::null());
        let rj = unsafe { std::ffi::CStr::from_ptr(r) }.to_string_lossy().into_owned();
        crate::mkpx_free_string(r);
        assert!(rj.contains("\"props\":[{\"id\":1"), "{rj}");
        assert!(rj.contains("\"actors\":[1]"), "{rj}");
        // Garbage errors cleanly.
        let junk = [7u8; 12];
        let e = mkps_import_prop(s, junk.as_ptr(), junk.len(), 0, 1, std::ptr::null());
        let ej = unsafe { std::ffi::CStr::from_ptr(e) }.to_string_lossy().into_owned();
        crate::mkpx_free_string(e);
        assert!(ej.contains("\"error\""), "{ej}");
        mkps_free(s);
    }

    /// The ADR-0001 mechanical check: for every SceneFps, an exported GIF decodes back with
    /// per-frame durations EXACTLY equal to frame_us().
    #[test]
    fn gif_timing_is_exact_for_every_rate() {
        let _guard = crate::EXPORT_TEST_LOCK.lock().unwrap();
        for fps in makapix_scene::model::SceneFps::ALL {
            let s = mkps_new(8, 8, fps.millifps());
            run(s, "SetFrameCount(2); GenPropSolid(4,4,#10E010FF); PlaceActorAt(1, 4, 4)");
            let mut len = 0u64;
            let p = mkps_export_gif(s, 1, &mut len);
            assert!(!p.is_null(), "export at {:?}", fps);
            let gif = unsafe { slice::from_raw_parts(p, len as usize) }.to_vec();
            crate::mkpx_free_bytes(p, len);
            assert_eq!(&gif[..6], b"GIF89a");
            let frames = makapix_codec::decode(&gif).expect("decode");
            assert_eq!(frames.len(), 2);
            for f in &frames {
                assert_eq!(
                    f.duration_us,
                    fps.frame_us(),
                    "{:?}: GIF delay must round-trip exactly (ADR-0001)",
                    fps
                );
            }
            mkps_free(s);
        }
    }

    #[test]
    fn gif_alpha_threshold_and_lossy_flag() {
        let _guard = crate::EXPORT_TEST_LOCK.lock().unwrap();
        // A half-transparent actor over nothing → thresholding happened.
        let s = mkps_new(8, 8, 12_500);
        run(s, "SetFrameCount(1); GenPropSolid(4,4,#FFFFFFFF); PlaceActorAt(1, 4, 4); SetBase(1, opacity, 100)");
        let mut len = 0u64;
        let p = mkps_export_gif(s, 1, &mut len);
        assert!(!p.is_null());
        crate::mkpx_free_bytes(p, len);
        assert_eq!(mkps_export_alpha_lossy(), 1, "semi-alpha was thresholded");
        mkps_free(s);

        // Fully opaque scene → not lossy.
        let s2 = mkps_new(8, 8, 12_500);
        run(s2, "SetFrameCount(1); SetBackground(#000000FF); GenPropSolid(4,4,#FFFFFFFF); PlaceActorAt(1, 4, 4)");
        let mut len2 = 0u64;
        let p2 = mkps_export_gif(s2, 1, &mut len2);
        assert!(!p2.is_null());
        crate::mkpx_free_bytes(p2, len2);
        assert_eq!(mkps_export_alpha_lossy(), 0);
        mkps_free(s2);
    }

    #[test]
    fn webp_export_and_progress_terminal() {
        let _guard = crate::EXPORT_TEST_LOCK.lock().unwrap();
        let s = mkps_new(8, 8, 25_000);
        run(s, "SetFrameCount(3); GenPropSolid(4,4,#4080FF80); PlaceActorAt(1, 4, 4)");
        let mut len = 0u64;
        let p = mkps_export_webp(s, 2, &mut len);
        assert!(!p.is_null() && len > 0);
        let webp = unsafe { slice::from_raw_parts(p, len as usize) }.to_vec();
        crate::mkpx_free_bytes(p, len);
        assert_eq!(&webp[..4], b"RIFF");
        assert_eq!(&webp[8..12], b"WEBP");
        // True alpha survives WEBP.
        let frames = makapix_codec::decode(&webp).expect("decode");
        assert_eq!(frames.len(), 3);
        assert!(frames[0].rgba.chunks_exact(4).any(|px| px[3] != 0 && px[3] != 255));
        // Progress ended at done == total == 2n.
        let packed = crate::mkpx_export_progress();
        let (done, total) = ((packed & 0xFFFF_FFFF) as u32, (packed >> 32) as u32);
        assert_eq!(total, 6);
        assert_eq!(done, 6);
        mkps_free(s);
    }
}
