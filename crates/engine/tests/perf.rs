//! Performance smoke (run with `--release --nocapture`). Not a correctness gate; prints
//! timings/memory for large animations to confirm the app stays responsive and bounded
//! (SPEC §23). Wall-clock here is test-only; the engine itself uses no real clock.

use makapix_engine::render;
use makapix_engine::tool::ToolKind;
use makapix_engine::Rgba8;
use makapix_engine::Session;
use std::time::Instant;

fn ms(d: std::time::Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

#[test]
fn perf_large_animation() {
    let frames = 500;
    let layers = 20;

    let t0 = Instant::now();
    let mut s = Session::new(64, 64);
    s.tool = ToolKind::Pencil;
    s.settings.brush_size = 2;
    for f in 0..frames {
        if f > 0 {
            s.add_frame();
        }
        for l in 0..layers {
            if l > 0 {
                s.add_layer();
            }
            s.settings.primary = Rgba8::rgb((f % 256) as u8, (l * 12 % 256) as u8, 200);
            let x = (f * 3 + l) % 60;
            let y = (f * 2 + l * 3) % 60;
            s.stroke_path(&[(x as i32, y as i32), (x as i32 + 5, y as i32 + 5)]);
        }
    }
    let build = t0.elapsed();

    let t1 = Instant::now();
    let mut sink = 0u64;
    for fr in &s.doc.frames {
        let flat = render::composite_frame(fr, 64, 64);
        sink = sink.wrapping_add(flat.to_rgba_bytes()[0] as u64);
    }
    let composite_all = t1.elapsed();

    let t2 = Instant::now();
    let bytes = s.save_bytes();
    let save = t2.elapsed();
    let t3 = Instant::now();
    let mut s2 = Session::empty();
    s2.load_bytes(&bytes).unwrap();
    let load = t3.elapsed();

    let mb = s.doc.memory_bytes() as f64 / (1024.0 * 1024.0);
    println!(
        "\n=== PERF: {} frames x {} layers ({} total layers) on 64x64 ===",
        frames,
        layers,
        frames * layers
    );
    println!("build (draw all):   {:8.1} ms  ({:.3} ms/layer)", ms(build), ms(build) / (frames * layers) as f64);
    println!("composite all {:>4}: {:8.1} ms  ({:.3} ms/frame)", frames, ms(composite_all), ms(composite_all) / frames as f64);
    println!(".mkpx save:         {:8.1} ms  -> {} KiB", ms(save), bytes.len() / 1024);
    println!(".mkpx load:         {:8.1} ms", ms(load));
    println!("resident memory:    {:8.1} MiB", mb);
    println!("roundtrip hash ok:  {}", s2.doc.content_hash() == s.doc.content_hash());
    let _ = sink;

    assert_eq!(s.doc.frames.len(), frames);
    assert!(mb < 1024.0, "memory {} MiB too high", mb);
    assert_eq!(s2.doc.content_hash(), s.doc.content_hash());
}
