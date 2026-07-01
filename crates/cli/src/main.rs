//! `mkpx` — the Tier-1 headless harness (SPEC §22). Runs an action script against the
//! engine, then evaluates colon-separated probes. Exit code is the CI gate:
//!   0 = all probes passed · 1 = an oracle/assert probe failed · 2 = script/IO error.
//!
//! Usage:
//!   mkpx run <script.txt | -> [PROBE ...]
//!   mkpx new <w> <h> -- <inline; actions; ...> [PROBE ...]
//!
//! Probes (colon-separated):
//!   ascii:F:L            state                 hash:F:L
//!   stats:F:L            pixel:F:L:X:Y         ramp:x0:y0:x1:y1:N
//!   thumb:F:L:W:H        render:F:OUT.png[:S]  composite:F:OUT.png[:S]
//!   assert.undo          assert.gradient:TOL   assert.roundtrip

use makapix_engine::probe;
use makapix_engine::render;
use makapix_engine::Session;
use std::process::exit;

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
            "ascii" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                let (w, h) = session.size();
                let buf = layer_buffer(&session, f, l);
                println!(
                    "# ascii frame={} layer={}\n{}",
                    f,
                    l,
                    probe::ascii(&buf, makapix_engine::geom::IRect::new(0, 0, w as u32, h as u32))
                );
            }
            "hash" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                println!("# hash frame={} layer={} {}", f, l, makapix_engine::util::hash_hex(session.layer_hash(f, l)));
            }
            "stats" => {
                let (f, l) = (idx(&parts, 1), idx(&parts, 2));
                print!("{}", probe::stats_text(&layer_buffer(&session, f, l)));
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
                print!("{}", probe::thumb(&layer_buffer(&session, f, l), w, h));
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

fn layer_buffer(s: &Session, f: usize, l: usize) -> makapix_engine::buffer::RgbaBuffer {
    let f = f.min(s.doc.frames.len() - 1);
    let l = l.min(s.doc.frames[f].layers.len() - 1);
    s.doc.frames[f].layers[l].pixels.clone()
}
fn composite(s: &Session, f: usize) -> makapix_engine::buffer::RgbaBuffer {
    let f = f.min(s.doc.frames.len() - 1);
    render::composite_frame(&s.doc.frames[f], s.doc.canvas_rect())
}
