//! `mkpx scene …` — the Animator's headless harness family, the mkpx loop's twin over a
//! `SceneSession`. Same exit-code contract: 0 = all probes passed · 1 = a probe failed ·
//! 2 = script/IO/usage error. Probes are colon-separated trailing args, evaluated in order.
//!
//! Probes: `state` · `mem` · `mem.os` · `eval:A:F` · `assert.eval:A:F:prop=VAL` ·
//! `ascii:F` · `hash:F` · `stats:F` · `thumb:F:W:H` · `render:F:OUT.png[:S]` ·
//! `assert.det:F` (warm-vs-cold compositor determinism)
//! (P3 adds `assert.roundtrip`, P4 the export probes.)

use crate::mem;
use crate::probe_util::{idx, verdict};
use makapix_engine::geom::IRect;
use makapix_engine::probe;
use makapix_scene::compose::{scene_frame, TransformCache, TRANSFORM_CACHE_BUDGET};
use makapix_scene::eval::ActorPose;
use makapix_scene::model::TrackProp;
use makapix_scene::SceneSession;

/// Entry point; `args` is everything after the `scene` token.
pub fn scene_main(args: &[String]) -> i32 {
    if args.is_empty() {
        eprintln!(
            "usage: mkpx scene run <script|-> [probes...]   |   mkpx scene new <w> <h> <millifps> [probes...]   |   mkpx scene import <w> <h> <millifps> <image> [--split] [--name NAME] [probes...]"
        );
        return 2;
    }
    let mut session = SceneSession::empty();
    let probe_start;
    match args[0].as_str() {
        "run" => {
            if args.len() < 2 {
                eprintln!("mkpx scene run needs a script path or '-'");
                return 2;
            }
            let src = if args[1] == "-" {
                use std::io::Read;
                let mut s = String::new();
                std::io::stdin().read_to_string(&mut s).ok();
                s
            } else {
                match std::fs::read_to_string(&args[1]) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("cannot read script '{}': {}", args[1], e);
                        return 2;
                    }
                }
            };
            if let Err(e) = run_script_with_imports(&mut session, &src) {
                eprintln!("script error: {}", e);
                return 2;
            }
            probe_start = 2;
        }
        "new" => {
            if args.len() < 4 {
                eprintln!("mkpx scene new needs <w> <h> <millifps>");
                return 2;
            }
            let w: u16 = args[1].parse().unwrap_or(0);
            let h: u16 = args[2].parse().unwrap_or(0);
            let mfps: u32 = args[3].parse().unwrap_or(0);
            let Some(fps) = makapix_scene::SceneFps::from_millifps(mfps) else {
                eprintln!("millifps must be one of 10000|12500|20000|25000|50000");
                return 2;
            };
            session = SceneSession::new(w, h, fps);
            probe_start = 4;
        }
        "load" => {
            if args.len() < 2 {
                eprintln!("mkpx scene load needs a .mkps path");
                return 2;
            }
            let bytes = match std::fs::read(&args[1]) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("cannot read '{}': {}", args[1], e);
                    return 2;
                }
            };
            if let Err(e) = session.load_bytes(&bytes) {
                eprintln!("load error: {}", e);
                return 2;
            }
            probe_start = 2;
        }
        "import" => {
            if args.len() < 5 {
                eprintln!("mkpx scene import needs <w> <h> <millifps> <image>");
                return 2;
            }
            let w: u16 = args[1].parse().unwrap_or(0);
            let h: u16 = args[2].parse().unwrap_or(0);
            let mfps: u32 = args[3].parse().unwrap_or(0);
            let Some(fps) = makapix_scene::SceneFps::from_millifps(mfps) else {
                eprintln!("millifps must be one of 10000|12500|20000|25000|50000");
                return 2;
            };
            session = SceneSession::new(w, h, fps);
            let bytes = match std::fs::read(&args[4]) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("cannot read image '{}': {}", args[4], e);
                    return 2;
                }
            };
            let mut split = false;
            let mut name = String::new();
            let mut i = 5usize;
            while i < args.len() && args[i].starts_with("--") {
                match args[i].as_str() {
                    "--split" => split = true,
                    "--name" => {
                        i += 1;
                        name = args.get(i).cloned().unwrap_or_default();
                    }
                    other => {
                        eprintln!("unknown import flag '{}'", other);
                        return 2;
                    }
                }
                i += 1;
            }
            match session.import_prop_bytes(&bytes, &name, split, true) {
                Ok(o) => eprintln!("# imported props={:?} actors={:?}", o.props, o.actors),
                Err(e) => {
                    eprintln!("import error: {}", e);
                    return 2;
                }
            }
            probe_start = i;
        }
        other => {
            eprintln!("unknown scene command '{}'", other);
            return 2;
        }
    }

    run_probes(&mut session, &args[probe_start..])
}

/// Run a scene script, handling the CLI-level `@import(path, name)` and
/// `@import-split(path, name)` directives — asset embedding for scripted scenes. File I/O
/// stays in the harness, never in the scene DSL; the imported prop's art is copied into the
/// session (ADR-0002 self-containment), and props number in creation order exactly as if
/// they were `GenProp` lines. Imports do not place actors — scripts place explicitly.
fn run_script_with_imports(session: &mut SceneSession, src: &str) -> Result<(), String> {
    for (ln, raw) in src.lines().enumerate() {
        let line = raw.trim();
        if let Some(rest) = line.strip_prefix("@import") {
            let (split, rest) = match rest.strip_prefix("-split") {
                Some(r) => (true, r),
                None => (false, rest),
            };
            let inner = rest
                .trim()
                .strip_prefix('(')
                .and_then(|s| s.strip_suffix(')'))
                .ok_or_else(|| format!("line {}: @import needs (path[, name])", ln + 1))?;
            let (path, name) = match inner.split_once(',') {
                Some((p, n)) => (p.trim(), n.trim()),
                None => (inner.trim(), ""),
            };
            let bytes = std::fs::read(path)
                .map_err(|e| format!("line {}: cannot read '{}': {}", ln + 1, path, e))?;
            session
                .import_prop_bytes(&bytes, name, split, false)
                .map_err(|e| format!("line {}: import '{}' failed: {}", ln + 1, path, e))?;
        } else {
            session
                .run_script(raw)
                .map_err(|e| format!("line {}: {}", ln + 1, e))?;
        }
    }
    Ok(())
}

/// Evaluate the trailing probe specs; returns the process exit code.
fn run_probes(session: &mut SceneSession, specs: &[String]) -> i32 {
    let mut failed = false;
    for spec in specs {
        let parts: Vec<&str> = spec.split(':').collect();
        match parts[0] {
            "state" => println!("{}", session.state_json()),
            "mem" => println!("# mem {}", session.mem_json()),
            "mem.os" => {
                let m = mem::os_mem();
                println!("# mem.os resident_bytes={} peak_bytes={}", m.resident, m.peak);
            }
            "eval" => {
                let a = idx(&parts, 1) as u32;
                let f = idx(&parts, 2) as u32;
                match session.eval_pose(a, f) {
                    Some(p) => {
                        let src = session.resolved_src_frame(a, f).unwrap_or(0);
                        println!(
                            "# eval actor={} frame={} x={} y={} rot={} scale={} fliph={} flipv={} opacity={} pivotx={} pivoty={} pose={} src={}",
                            a, f, p.x, p.y, p.rot_md, p.scale_milli, p.flip_h, p.flip_v,
                            p.opacity, p.pivot_x_milli, p.pivot_y_milli, p.pose, src
                        );
                    }
                    None => {
                        println!("# eval actor={} frame={} MISSING", a, f);
                        failed = true;
                    }
                }
            }
            "ascii" => {
                let f = idx(&parts, 1) as u32;
                let buf = session.composite(f);
                let (w, h) = session.size();
                println!("# ascii frame={}", f);
                println!("{}", probe::ascii(&buf, IRect::new(0, 0, w as u32, h as u32)));
            }
            "hash" => {
                let f = idx(&parts, 1) as u32;
                println!("# hash frame={} {:016x}", f, session.frame_hash(f));
            }
            "stats" => {
                let f = idx(&parts, 1) as u32;
                let buf = session.composite(f);
                let (w, h) = session.size();
                println!(
                    "# stats frame={} {}",
                    f,
                    probe::stats_text(&buf, IRect::new(0, 0, w as u32, h as u32))
                );
            }
            "thumb" => {
                let f = idx(&parts, 1) as u32;
                let tw = idx(&parts, 2).max(1) as u32;
                let th = idx(&parts, 3).max(1) as u32;
                let buf = session.composite(f);
                println!("# thumb frame={}", f);
                println!("{}", probe::thumb(&buf, tw, th));
            }
            "render" | "composite" => {
                let f = idx(&parts, 1) as u32;
                let out = parts.get(2).copied().unwrap_or("out.png");
                let scale: u32 = parts.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
                let (w, h) = session.size();
                let bytes = session.composite_bytes(f);
                let png = crate::png::encode_rgba(w as u32, h as u32, &bytes, scale);
                if let Err(e) = std::fs::write(out, &png) {
                    eprintln!("render write failed '{}': {}", out, e);
                    failed = true;
                } else {
                    println!("# render frame={} -> {} scale={}", f, out, scale);
                }
            }
            "export.gif" => {
                // export.gif:OUT.gif[:S]
                let out = parts.get(1).copied().unwrap_or("out.gif");
                let scale: u32 = parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(1);
                let mut progress = |_d: usize, _t: usize| true;
                match session.export_gif(scale, &mut progress) {
                    Ok((bytes, lossy)) => {
                        if let Err(e) = std::fs::write(out, &bytes) {
                            eprintln!("export.gif write failed '{}': {}", out, e);
                            failed = true;
                        } else {
                            println!("# export.gif -> {} bytes={} alpha_lossy={}", out, bytes.len(), lossy);
                        }
                    }
                    Err(e) => {
                        eprintln!("export.gif failed: {}", e);
                        failed = true;
                    }
                }
            }
            "export.webp" => {
                let out = parts.get(1).copied().unwrap_or("out.webp");
                let scale: u32 = parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(1);
                let mut progress = |_d: usize, _t: usize| true;
                match session.export_webp(scale, &mut progress) {
                    Ok(bytes) => {
                        if let Err(e) = std::fs::write(out, &bytes) {
                            eprintln!("export.webp write failed '{}': {}", out, e);
                            failed = true;
                        } else {
                            println!("# export.webp -> {} bytes={}", out, bytes.len());
                        }
                    }
                    Err(e) => {
                        eprintln!("export.webp failed: {}", e);
                        failed = true;
                    }
                }
            }
            "save" => {
                // save:OUT.mkps — write the session's plain .mkps (fixture generation, goldens).
                let out = parts.get(1).copied().unwrap_or("out.mkps");
                if let Err(e) = std::fs::write(out, session.save_bytes()) {
                    eprintln!("save write failed '{}': {}", out, e);
                    failed = true;
                } else {
                    println!("# save -> {}", out);
                }
            }
            "assert.roundtrip" => {
                let bytes = session.save_bytes();
                let mut fresh = SceneSession::empty();
                let ok = fresh.load_bytes(&bytes).is_ok()
                    && fresh.scene.content_hash() == session.scene.content_hash();
                println!("# assert.roundtrip VERDICT: {}", verdict(ok));
                failed |= !ok;
            }
            "assert.det" => {
                // The transform cache can never change output: composite twice through the
                // session (second call warm), then cold through a FRESH cache; all equal.
                let f = idx(&parts, 1) as u32;
                let h1 = session.frame_hash(f);
                let h2 = session.frame_hash(f); // warm
                let cold = scene_frame(
                    &session.scene,
                    &mut TransformCache::new(TRANSFORM_CACHE_BUDGET),
                    f,
                );
                let h3 = cold.content_hash() as u64;
                let ok = h1 == h2 && h2 == h3;
                println!("# assert.det frame={} VERDICT: {}", f, verdict(ok));
                failed |= !ok;
            }
            "assert.eval" => {
                // assert.eval:A:F:prop=VAL — flips accept true/false or 0/1.
                let a = idx(&parts, 1) as u32;
                let f = idx(&parts, 2) as u32;
                let ok = match (parts.get(3), session.eval_pose(a, f)) {
                    (Some(expr), Some(p)) => match expr.split_once('=') {
                        Some((prop, val)) => check_eval(session, a, f, &p, prop, val),
                        None => false,
                    },
                    _ => false,
                };
                println!("# assert.eval {} VERDICT: {}", spec, verdict(ok));
                failed |= !ok;
            }
            other => {
                eprintln!("unknown probe '{}'", other);
                failed = true;
            }
        }
    }
    if failed {
        1
    } else {
        0
    }
}

fn check_eval(
    session: &SceneSession,
    actor: u32,
    frame: u32,
    p: &ActorPose,
    prop: &str,
    val: &str,
) -> bool {
    let expect_bool = |v: bool| -> bool {
        matches!((v, val), (true, "true" | "1") | (false, "false" | "0"))
    };
    let expect_i = |v: i64| -> bool { val.parse::<i64>().map(|e| e == v).unwrap_or(false) };
    match TrackProp::parse(prop) {
        Some(TrackProp::X) => expect_i(p.x as i64),
        Some(TrackProp::Y) => expect_i(p.y as i64),
        Some(TrackProp::Rot) => expect_i(p.rot_md as i64),
        Some(TrackProp::Scale) => expect_i(p.scale_milli as i64),
        Some(TrackProp::FlipH) => expect_bool(p.flip_h),
        Some(TrackProp::FlipV) => expect_bool(p.flip_v),
        Some(TrackProp::Opacity) => expect_i(p.opacity as i64),
        Some(TrackProp::PivotX) => expect_i(p.pivot_x_milli as i64),
        Some(TrackProp::PivotY) => expect_i(p.pivot_y_milli as i64),
        Some(TrackProp::Pose) => expect_i(p.pose as i64),
        None if prop == "src" => {
            let src = session.resolved_src_frame(actor, frame).unwrap_or(u32::MAX);
            expect_i(src as i64)
        }
        None => false,
    }
}
