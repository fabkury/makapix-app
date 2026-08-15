//! One-off appraisal bench: time the shipped streaming GIF / animated-WebP encoders on
//! timelapse-shaped content (progressive pixel-art drawing, limited palette, cumulative
//! frames), with the per-frame integer upscale the timelapse export would use.
//!
//! Usage: replaybench <gif|webp|upscale|png> <w> <h> <scale> <frames>

use std::time::Instant;

// Deterministic LCG so Windows and Android runs see identical content.
struct Lcg(u64);
impl Lcg {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.0 >> 33
    }
    fn range(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

const PALETTE: [[u8; 4]; 24] = [
    [20, 12, 28, 255], [68, 36, 52, 255], [48, 52, 109, 255], [78, 74, 78, 255],
    [133, 76, 48, 255], [52, 101, 36, 255], [208, 70, 72, 255], [117, 113, 97, 255],
    [89, 125, 206, 255], [210, 125, 44, 255], [133, 149, 161, 255], [109, 170, 44, 255],
    [210, 170, 153, 255], [109, 194, 202, 255], [218, 212, 94, 255], [222, 238, 214, 255],
    [40, 30, 60, 255], [120, 60, 90, 255], [60, 120, 90, 255], [90, 60, 120, 255],
    [180, 100, 60, 255], [60, 100, 180, 255], [240, 200, 120, 255], [120, 200, 240, 255],
];

/// Progressive drawing: each frame paints `blobs` small filled discs onto the running canvas,
/// then snapshots it. Mimics a timelapse sampled every ~10 recorded actions.
fn make_frames(w: usize, h: usize, n: usize, blobs: usize) -> Vec<Vec<u8>> {
    let mut canvas = vec![0u8; w * h * 4];
    // background fill (first "action")
    for px in canvas.chunks_exact_mut(4) {
        px.copy_from_slice(&[34, 32, 52, 255]);
    }
    let mut rng = Lcg(42);
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        for _ in 0..blobs {
            let color = PALETTE[rng.range(PALETTE.len())];
            let cx = rng.range(w) as i32;
            let cy = rng.range(h) as i32;
            let r = (1 + rng.range(4)) as i32; // brush radius 1..4 source pixels
            for dy in -r..=r {
                for dx in -r..=r {
                    if dx * dx + dy * dy > r * r {
                        continue;
                    }
                    let (x, y) = (cx + dx, cy + dy);
                    if x < 0 || y < 0 || x >= w as i32 || y >= h as i32 {
                        continue;
                    }
                    let i = (y as usize * w + x as usize) * 4;
                    canvas[i..i + 4].copy_from_slice(&color);
                }
            }
        }
        out.push(canvas.clone());
    }
    out
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 6 {
        eprintln!("usage: replaybench <gif|webp|upscale|png> <w> <h> <scale> <frames>");
        std::process::exit(2);
    }
    let mode = args[1].as_str();
    let w: usize = args[2].parse().unwrap();
    let h: usize = args[3].parse().unwrap();
    let scale: u32 = args[4].parse().unwrap();
    let n: usize = args[5].parse().unwrap();

    let t0 = Instant::now();
    let frames = make_frames(w, h, n, 8);
    let gen_ms = t0.elapsed().as_secs_f64() * 1000.0;

    match mode {
        "upscale" => {
            let t = Instant::now();
            let mut sink = 0u64;
            for f in &frames {
                let up = makapix_codec::upscale_nearest(w as u32, h as u32, f, scale);
                sink = sink.wrapping_add(up[up.len() / 2] as u64);
            }
            let ms = t.elapsed().as_secs_f64() * 1000.0;
            println!(
                "upscale {}x{} x{} frames={} gen_ms={:.0} total_ms={:.1} ms/frame={:.2} (sink {})",
                w, h, scale, n, gen_ms, ms, ms / n as f64, sink
            );
        }
        "png" => {
            // per-frame PNG at upscaled size (the "PNG sequence" pipeline option)
            let t = Instant::now();
            let mut bytes = 0usize;
            for f in &frames {
                let up = makapix_codec::upscale_nearest(w as u32, h as u32, f, scale);
                let png = makapix_codec::encode_png((w as u32) * scale, (h as u32) * scale, &up)
                    .expect("png");
                bytes += png.len();
            }
            let ms = t.elapsed().as_secs_f64() * 1000.0;
            println!(
                "png {}x{} x{} frames={} gen_ms={:.0} total_ms={:.0} ms/frame={:.1} out_bytes={} ({:.0} KiB/frame)",
                w, h, scale, n, gen_ms, ms, ms / n as f64, bytes, bytes as f64 / n as f64 / 1024.0
            );
        }
        "gif" | "webp" => {
            let mut it = frames.into_iter().map(|f| (f, 33_333u32));
            let count = n;
            let mut progress = |_done: usize, _total: usize| true;
            let t = Instant::now();
            let out = if mode == "gif" {
                let mut flattened = false;
                makapix_codec::encode_gif_streaming(
                    w as u32, h as u32, count, || it.next(), scale, &mut progress, &mut flattened,
                )
            } else {
                makapix_codec::encode_animated_webp_streaming(
                    w as u32, h as u32, count, || it.next(), scale, &mut progress,
                )
            }
            .expect("encode");
            let ms = t.elapsed().as_secs_f64() * 1000.0;
            println!(
                "{} {}x{} x{} ({}px) frames={} gen_ms={:.0} total_ms={:.0} ms/frame={:.1} out_bytes={} ({:.1} MiB)",
                mode, w, h, scale, (w as u32) * scale, n, gen_ms, ms, ms / n as f64,
                out.len(), out.len() as f64 / 1024.0 / 1024.0
            );
        }
        "snap" => {
            // usage: replaybench snap <w-ignored> <h-ignored> <n_checkpoints> <frames-ignored> <script>
            // Replays <script> in <n_checkpoints> chunks; at each checkpoint takes a COW
            // frame-vector snapshot (Arc bumps only), then censuses retained memory by pointer.
            let n_checkpoints = scale as usize;
            let script_path = args.get(6).expect("snap needs a script path as 6th arg");
            let src = std::fs::read_to_string(script_path).expect("read script");
            let lines: Vec<&str> = src.lines().collect();
            let chunk = lines.len().div_ceil(n_checkpoints);
            let mut session = makapix_engine::Session::empty();
            // checkpoints: per checkpoint, per frame-layer, the buffer's Arc<TileTable>
            let mut checkpoints: Vec<Vec<std::sync::Arc<makapix_engine::buffer::TileTable>>> =
                Vec::new();
            let mut snap_ms_total = 0.0f64;
            let t_all = Instant::now();
            for c in lines.chunks(chunk) {
                session.run_script(&c.join("\n")).expect("script");
                let t = Instant::now();
                let mut tables = Vec::new();
                for f in &session.doc.frames {
                    for l in &f.layers {
                        tables.push(l.pixels.snapshot());
                    }
                }
                snap_ms_total += t.elapsed().as_secs_f64() * 1000.0;
                checkpoints.push(tables);
            }
            let run_ms = t_all.elapsed().as_secs_f64() * 1000.0;
            // census: unique tables and unique tiles across ALL checkpoints, by pointer
            use std::collections::HashSet;
            let mut table_ptrs: HashSet<usize> = HashSet::new();
            let mut tile_ptrs: HashSet<usize> = HashSet::new();
            let mut table_bytes = 0usize;
            for cp in &checkpoints {
                for t in cp {
                    if table_ptrs.insert(std::sync::Arc::as_ptr(t) as usize) {
                        table_bytes += t.len() * std::mem::size_of::<Option<std::sync::Arc<makapix_engine::buffer::Tile>>>();
                        for slot in t.iter().flatten() {
                            tile_ptrs.insert(std::sync::Arc::as_ptr(slot) as usize);
                        }
                    }
                }
            }
            // live doc unique tiles for reference (shared tiles are counted once overall)
            let mut live_tiles: HashSet<usize> = HashSet::new();
            for f in &session.doc.frames {
                for l in &f.layers {
                    for slot in l.pixels.snapshot().iter().flatten() {
                        live_tiles.insert(std::sync::Arc::as_ptr(slot) as usize);
                    }
                }
            }
            let snap_only: usize = tile_ptrs.difference(&live_tiles).count();
            println!(
                "snap script={} checkpoints={} run_ms={:.0} snap_ms_total={:.2} \
                 unique_tables={} table_bytes={} unique_tiles_all={} tile_bytes_all={} \
                 live_tiles={} snapshot_only_tiles={} snapshot_only_bytes={}",
                script_path, checkpoints.len(), run_ms, snap_ms_total,
                table_ptrs.len(), table_bytes,
                tile_ptrs.len(), tile_ptrs.len() * 4096,
                live_tiles.len(), snap_only, snap_only * 4096
            );
        }
        "comp" => {
            // usage: replaybench comp 1 1 <reps> 0 <script> — composite cost at source res
            let reps = scale as usize;
            let script_path = args.get(6).expect("comp needs a script path");
            let src = std::fs::read_to_string(script_path).expect("read script");
            let mut session = makapix_engine::Session::empty();
            session.run_script(&src).expect("script");
            let rect = session.doc.canvas_rect();
            let t = Instant::now();
            let mut sink = 0u64;
            for i in 0..reps {
                let f = i % session.doc.frames.len();
                let buf = makapix_engine::render::composite_frame(&session.doc.frames[f], rect);
                sink = sink.wrapping_add(buf.tile_table_bytes() as u64);
            }
            let ms = t.elapsed().as_secs_f64() * 1000.0;
            println!(
                "comp script={} reps={} total_ms={:.1} ms/frame={:.3} (sink {})",
                script_path, reps, ms, ms / reps as f64, sink
            );
        }
        other => {
            eprintln!("unknown mode {}", other);
            std::process::exit(2);
        }
    }
}
