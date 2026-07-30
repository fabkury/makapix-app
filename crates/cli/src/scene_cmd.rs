//! `mkpx scene …` — the Animator's headless harness family, the mkpx loop's twin over a
//! `SceneSession`. Same exit-code contract: 0 = all probes passed · 1 = a probe failed ·
//! 2 = script/IO/usage error. Probes are colon-separated trailing args, evaluated in order.
//!
//! P1 probes: `state` · `mem` · `mem.os` · `eval:A:F` · `assert.eval:A:F:prop=VAL`
//! (P2 adds the pixel probes, P3 `assert.roundtrip`, P4 the export probes.)

use crate::mem;
use crate::probe_util::{idx, verdict};
use makapix_scene::eval::ActorPose;
use makapix_scene::model::TrackProp;
use makapix_scene::SceneSession;

/// Entry point; `args` is everything after the `scene` token.
pub fn scene_main(args: &[String]) -> i32 {
    if args.is_empty() {
        eprintln!("usage: mkpx scene run <script|-> [probes...]   |   mkpx scene new <w> <h> <millifps> [probes...]");
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
            if let Err(e) = session.run_script(&src) {
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
        other => {
            eprintln!("unknown scene command '{}'", other);
            return 2;
        }
    }

    run_probes(&mut session, &args[probe_start..])
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
