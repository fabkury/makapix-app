//! `mkpx` — the Tier-1 headless harness (SPEC §22). Runs an action script against the
//! engine, then evaluates colon-separated probes. Exit code is the CI gate:
//!   0 = all probes passed · 1 = an oracle/assert probe failed · 2 = script/IO error.
//!
//! Usage:
//!   mkpx run <script.txt | -> [PROBE ...]
//!   mkpx new <w> <h> -- <inline; actions; ...> [PROBE ...]
//!   mkpx gen <w> <h> <frames> <layers> <seed> <out.mkpx> [PROBE ...]
//!   mkpx load <file.mkpx> [--run <script|->] [PROBE ...]
//!   mkpx import <w> <h> <image> [--pre <script>] [--as-layer] [--mode fit|stretch|crop]
//!               [--start N] [--times N] [PROBE ...]
//!
//! `import` (memory-audit lab tool, 2026-07-29) drives the exact decode+import path the app's
//! `mkpx_import` FFI uses: create a <w>×<h> session, optionally run a `--pre` DSL script first
//! (e.g. to build a near-budget document), then decode <image> once and run
//! `Session::import_decoded` `--times` times (start frame advancing by 1 each round with
//! `--as-layer`, mimicking a user importing repeatedly). Timings and decoded sizes go to stdout
//! as a `# import` line; combine with `mem`/`mem.os` probes to measure the import transient.
//!
//! `gen` builds a document whose every layer is full seeded noise (`tool::noise_fill`) by direct
//! construction — NO undo history, unlike scripted AddFrame/FillNoise — then saves it: the
//! resting-document memory floor for stress scaling. `load` loads a .mkpx and runs probes
//! (also history-free). Timings go to stderr as `# gen ...` lines.
//!
//! Probes (colon-separated):
//!   ascii:F:L            state                 hash:F:L
//!   stats:F:L            pixel:F:L:X:Y         ramp:x0:y0:x1:y1:N
//!   thumb:F:L:W:H        render:F:OUT.png[:S]  composite:F:OUT.png[:S]
//!   assert.undo          assert.gradient:TOL   assert.roundtrip
//!   mem                  mem.os                usedcolors            hash.doc
//!
//! `load --run <script|->` replays a script onto the loaded document — the replay-Journal
//! validation path (chapter base + prefix-stripped action tail; `#` lines pass through).
//!
//! `mem` prints the engine-accounted memory census (tile-deduped; see `probe::mem_report`);
//! `mem.os` prints the process's OS-level resident/peak bytes. Probes run in order, so placing
//! `mem.os` after `assert.roundtrip` captures the save/load transient in the peak.

use makapix_engine::probe;
use makapix_engine::render;
use makapix_engine::Session;
use std::process::exit;

mod mem;
mod png;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: mkpx run <script|-> [probes...]   |   mkpx new <w> <h> [probes...]");
        exit(2);
    }
    let mut session = Session::empty();
    let probe_start;
    match args[1].as_str() {
        "run" => {
            if args.len() < 3 {
                eprintln!("mkpx run needs a script path or '-'");
                exit(2);
            }
            let src = if args[2] == "-" {
                use std::io::Read;
                let mut s = String::new();
                std::io::stdin().read_to_string(&mut s).ok();
                s
            } else {
                match std::fs::read_to_string(&args[2]) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("cannot read {}: {}", args[2], e);
                        exit(2);
                    }
                }
            };
            if let Err(e) = session.run_script(&src) {
                eprintln!("script error: {}", e);
                exit(2);
            }
            probe_start = 3;
        }
        "new" => {
            if args.len() < 4 {
                eprintln!("mkpx new needs <w> <h>");
                exit(2);
            }
            let w: u16 = args[2].parse().unwrap_or(64);
            let h: u16 = args[3].parse().unwrap_or(64);
            session = Session::new(w, h);
            probe_start = 4;
        }
        "gen" => {
            if args.len() < 8 {
                eprintln!("mkpx gen needs <w> <h> <frames> <layers> <seed> <out.mkpx>");
                exit(2);
            }
            let w: u16 = args[2].parse().unwrap_or(64);
            let h: u16 = args[3].parse().unwrap_or(64);
            let frames: usize = args[4].parse().unwrap_or(1);
            let layers: usize = args[5].parse().unwrap_or(1);
            let seed0: u64 = args[6].parse().unwrap_or(1);
            session = gen_noise_doc(w, h, frames.max(1), layers.max(1), seed0, &args[7]);
            probe_start = 8;
        }
        "load" => {
            if args.len() < 3 {
                eprintln!("mkpx load needs a .mkpx path");
                exit(2);
            }
            let bytes = match std::fs::read(&args[2]) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("cannot read {}: {}", args[2], e);
                    exit(2);
                }
            };
            let t0 = std::time::Instant::now();
            if let Err(e) = session.load_bytes(&bytes) {
                eprintln!("load error: {:?}", e);
                exit(2);
            }
            let n = bytes.len();
            drop(bytes); // free the file buffer before probes so `mem.os` resident is doc-only
            println!("# load bytes={} ms={:.1}", n, t0.elapsed().as_secs_f64() * 1000.0);
            // Optional `--run <script|->`: replay a script onto the loaded document — the
            // replay-Journal validation path (a chapter base + its action tail; timestamps
            // must be stripped by the caller, `#` directive lines pass through). A flag, not
            // a probe: probe specs split on ':' and Windows paths carry drive colons.
            probe_start = if args.get(3).map(String::as_str) == Some("--run") {
                let path = match args.get(4) {
                    Some(p) => p,
                    None => {
                        eprintln!("--run needs a script path or '-'");
                        exit(2);
                    }
                };
                let src = if path == "-" {
                    use std::io::Read;
                    let mut s = String::new();
                    std::io::stdin().read_to_string(&mut s).ok();
                    s
                } else {
                    match std::fs::read_to_string(path) {
                        Ok(s) => s,
                        Err(e) => {
                            eprintln!("cannot read {}: {}", path, e);
                            exit(2);
                        }
                    }
                };
                let t1 = std::time::Instant::now();
                if let Err(e) = session.run_script(&src) {
                    eprintln!("script error: {}", e);
                    exit(2);
                }
                println!(
                    "# run lines={} ms={:.1}",
                    src.lines().count(),
                    t1.elapsed().as_secs_f64() * 1000.0
                );
                5
            } else {
                3
            };
        }
        "import" => {
            // Memory-audit lab tool: the same codec::decode → import_decoded path as mkpx_import.
            if args.len() < 5 {
                eprintln!("mkpx import needs <w> <h> <image> [--pre <script>] [--as-layer] [--mode fit|stretch|crop] [--start N] [--times N]");
                exit(2);
            }
            let w: u16 = args[2].parse().unwrap_or(64);
            let h: u16 = args[3].parse().unwrap_or(64);
            session = Session::new(w, h);
            let image_path = &args[4];
            let mut i = 5;
            let mut pre: Option<String> = None;
            let mut as_layer = false;
            let mut mode = makapix_engine::import::ScaleMode::Fit;
            let mut start: usize = 0;
            let mut times: usize = 1;
            while i < args.len() && args[i].starts_with("--") {
                match args[i].as_str() {
                    "--pre" => {
                        i += 1;
                        pre = args.get(i).map(|p| match std::fs::read_to_string(p) {
                            Ok(s) => s,
                            Err(e) => {
                                eprintln!("cannot read {}: {}", p, e);
                                exit(2);
                            }
                        });
                    }
                    "--as-layer" => as_layer = true,
                    "--mode" => {
                        i += 1;
                        mode = match args.get(i).map(String::as_str) {
                            Some("stretch") => makapix_engine::import::ScaleMode::Stretch,
                            Some("crop") => makapix_engine::import::ScaleMode::Crop,
                            _ => makapix_engine::import::ScaleMode::Fit,
                        };
                    }
                    "--start" => {
                        i += 1;
                        start = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(0);
                    }
                    "--times" => {
                        i += 1;
                        times = args.get(i).and_then(|s| s.parse().ok()).unwrap_or(1).max(1);
                    }
                    other => {
                        eprintln!("unknown import flag '{}'", other);
                        exit(2);
                    }
                }
                i += 1;
            }
            if let Some(src) = pre {
                if let Err(e) = session.run_script(&src) {
                    eprintln!("pre-script error: {}", e);
                    exit(2);
                }
            }
            let bytes = match std::fs::read(image_path) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("cannot read {}: {}", image_path, e);
                    exit(2);
                }
            };
            let file_bytes = bytes.len();
            let t0 = std::time::Instant::now();
            let frames = match makapix_codec::decode(&bytes) {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("decode error: {}", e);
                    exit(2);
                }
            };
            drop(bytes); // the decoded frames are the interesting transient, not the file
            let decode_ms = t0.elapsed().as_secs_f64() * 1000.0;
            let decoded_bytes: usize = frames.iter().map(|f| f.rgba.len()).sum();
            let decoded_frames = frames.len();
            let t1 = std::time::Instant::now();
            for k in 0..times {
                let cfg = makapix_engine::import::ImportConfig {
                    mode,
                    anchor: makapix_engine::import::Anchor::Center,
                    start_frame: start + if as_layer { k } else { 0 },
                    as_layer,
                    crop_rect: None,
                };
                session.import_decoded(&frames, cfg);
            }
            let import_ms = t1.elapsed().as_secs_f64() * 1000.0;
            drop(frames); // free the decoded set (as the app does) so post-import probes see doc-only resident; the peak retains the transient
            println!(
                "# import file_bytes={} decoded_frames={} decoded_bytes={} times={} decode_ms={:.1} import_ms={:.1}",
                file_bytes,
                decoded_frames,
                decoded_bytes,
                times,
                decode_ms,
                import_ms
            );
            probe_start = i;
        }
        other => {
            eprintln!("unknown command '{}'", other);
            exit(2);
        }
    }

    let mut failed = false;
    for spec in &args[probe_start..] {
        let parts: Vec<&str> = spec.split(':').collect();
        match parts[0] {
            "state" => println!("{}", session.state_json()),
            "usedcolors" => println!("{}", session.used_colors_json()),
            "mem" => println!("# mem {}", session.mem_json()),
            "mem.os" => {
                let m = mem::os_mem();
                println!("# mem.os resident_bytes={} peak_bytes={}", m.resident, m.peak);
            }
            "ascii" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                // Window on the canvas rect: layer buffers are storage-sized (canvas + gutter,
                // the canvas at `doc.origin()`), so a (0,0)-anchored window would show gutter.
                let buf = layer_buffer(&session, f, l);
                println!(
                    "# ascii frame={} layer={}\n{}",
                    f,
                    l,
                    probe::ascii(&buf, session.doc.canvas_rect())
                );
            }
            "hash" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                println!("# hash frame={} layer={} {}", f, l, makapix_engine::util::hash_hex(session.layer_hash(f, l)));
            }
            "hash.doc" => {
                // Whole-document content hash — the replay-validation oracle (NB it excludes
                // palettes/active_frame/selection by design; see document.rs content_hash).
                println!("# hash.doc {}", makapix_engine::util::hash_hex(session.doc.content_hash()));
            }
            "stats" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                // Content fields (count/bbox) windowed on the canvas, bbox in canvas coords like
                // the `pixel` probe; tile/memory numbers still describe the real storage buffer.
                print!("{}", probe::stats_text(&layer_buffer(&session, f, l), session.doc.canvas_rect()));
            }
            "pixel" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                let (x, y) = (iarg(&parts, 3), iarg(&parts, 4));
                println!("# pixel ({},{}) {}", x, y, session.pixel(f, l, x, y).to_hex());
            }
            "ramp" => {
                let p0 = makapix_engine::geom::Point::new(iarg(&parts, 1), iarg(&parts, 2));
                let p1 = makapix_engine::geom::Point::new(iarg(&parts, 3), iarg(&parts, 4));
                let n = idx(&parts, 5).max(2);
                let buf = composite(&session, 0);
                print!("{}", probe::ramp(&buf, p0, p1, n));
            }
            "thumb" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                let (w, h) = (idx(&parts, 3).max(1) as u32, idx(&parts, 4).max(1) as u32);
                // Thumbnail the canvas window, not the storage buffer (which would letterbox the
                // drawing inside the transparent gutter).
                let canvas = layer_buffer(&session, f, l).subimage(session.doc.canvas_rect());
                print!("{}", probe::thumb(&canvas, w, h));
            }
            "render" | "composite" | "display" => {
                let f = idx(&parts, 1);
                let out = parts.get(2).copied().unwrap_or("out.png");
                let scale: u32 = parts.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
                let (w, h) = session.size();
                let bytes = if parts[0] == "display" {
                    session.display_bytes(false, false, true)
                } else {
                    session.composite_frame_bytes(f)
                };
                let png = png::encode_rgba(w as u32, h as u32, &bytes, scale);
                if let Err(e) = std::fs::write(out, &png) {
                    eprintln!("cannot write {}: {}", out, e);
                    failed = true;
                } else {
                    println!("# wrote {} ({}x{} scale {})", out, w, h, scale);
                }
            }
            "assert.undo" => {
                let ok = session.assert_undo_restores();
                println!("# assert.undo VERDICT: {}", verdict(ok));
                failed |= !ok;
            }
            "assert.gradient" => {
                let tol: u8 = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
                match session.assert_last_gradient(tol) {
                    Some(o) => {
                        println!("# oracle.gradient max_delta={} tol={} VERDICT: {}", o.max_delta, tol, verdict(o.ok));
                        failed |= !o.ok;
                    }
                    None => {
                        println!("# oracle.gradient: no gradient applied VERDICT: FAIL");
                        failed = true;
                    }
                }
            }
            "assert.roundtrip" => {
                let bytes = session.save_bytes();
                let mut s2 = Session::empty();
                let ok = s2.load_bytes(&bytes).is_ok()
                    && s2.doc.content_hash() == session.doc.content_hash();
                println!("# assert.roundtrip VERDICT: {}", verdict(ok));
                failed |= !ok;
            }
            other => {
                eprintln!("unknown probe '{}'", other);
                failed = true;
            }
        }
    }

    exit(if failed { 1 } else { 0 });
}

fn verdict(ok: bool) -> &'static str {
    if ok {
        "PASS"
    } else {
        "FAIL"
    }
}

fn idx(parts: &[&str], k: usize) -> usize {
    parts.get(k).and_then(|s| s.parse().ok()).unwrap_or(0)
}
fn iarg(parts: &[&str], k: usize) -> i32 {
    parts.get(k).and_then(|s| s.parse().ok()).unwrap_or(0)
}

/// Build a `frames`×`layers` document whose every layer is full canvas noise, by DIRECT document
/// construction (no Session actions, so no undo history — the resting-document floor), save it to
/// `out`, and return the session holding it. Seeds increment per layer from `seed0`, matching what
/// a `FillNoise(seed)` script with the same seed order produces.
fn gen_noise_doc(w: u16, h: u16, frames: usize, layers: usize, seed0: u64, out: &str) -> Session {
    use makapix_engine::document::{BlendMode, Frame, Layer};
    use makapix_engine::buffer::RgbaBuffer;
    use makapix_engine::tool;

    let mut session = Session::new(w, h);
    let storage = session.doc.storage();
    let canvas = session.doc.canvas_rect();
    let t0 = std::time::Instant::now();
    let mut seed = seed0;
    let mut fs = Vec::with_capacity(frames);
    for fi in 0..frames {
        let mut ls = Vec::with_capacity(layers);
        for li in 0..layers {
            let mut pixels = RgbaBuffer::from_size(storage);
            tool::noise_fill(&mut pixels, canvas, seed);
            seed += 1;
            ls.push(Layer {
                id: (fi * layers + li + 1) as u32,
                name: format!("Layer {}", li + 1),
                visible: true,
                locked: false,
                opacity: 255,
                blend: BlendMode::Normal,
                pixels,
            });
        }
        fs.push(Frame { id: (fi + 1) as u32, duration_us: 100_000, layers: ls, active_layer: 0 });
    }
    session.doc.frames = fs;
    let build_ms = t0.elapsed().as_secs_f64() * 1000.0;

    let t1 = std::time::Instant::now();
    let bytes = session.save_bytes();
    let save_ms = t1.elapsed().as_secs_f64() * 1000.0;
    let t2 = std::time::Instant::now();
    if let Err(e) = std::fs::write(out, &bytes) {
        eprintln!("cannot write {}: {}", out, e);
        exit(2);
    }
    let write_ms = t2.elapsed().as_secs_f64() * 1000.0;
    println!(
        "# gen {}x{} frames={} layers={} build_ms={:.1} save_ms={:.1} write_ms={:.1} file_bytes={}",
        w,
        h,
        frames,
        layers,
        build_ms,
        save_ms,
        write_ms,
        bytes.len()
    );
    session
}

fn layer_buffer(s: &Session, f: usize, l: usize) -> makapix_engine::buffer::RgbaBuffer {
    let f = f.min(s.doc.frames.len() - 1);
    let l = l.min(s.doc.frames[f].layers.len() - 1);
    s.doc.frames[f].layers[l].pixels.clone()
}
fn composite(s: &Session, f: usize) -> makapix_engine::buffer::RgbaBuffer {
    let f = f.min(s.doc.frames.len() - 1);
    render::composite_frame(&s.doc.frames[f], s.doc.canvas_rect())
}
