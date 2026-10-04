//! Writes seed inputs into `corpus/<target>/` for three targets (run from `fuzz/`):
//! `.mkpx` documents for `fuzz_load_mkpx`, their compact-envelope forms for
//! `fuzz_mkpx_open`, and small image files for `fuzz_codec_import`.
//!
//! The seeds aim for *format diversity*, not size: empty (INDEXED/absent tiles),
//! scripted drawings (RLE-friendly runs + tile-dict dedup across duplicated frames),
//! noise (RAW tiles), and palette/blend/opacity metadata — so the coverage-guided
//! mutator starts with every chunk type and tile encoding already in the corpus.
//! `tools/fuzz/run_fuzz.sh` runs this automatically when a target's corpus is empty.
//! Every seed has a fixed name and fixed content, so a rerun overwrites in place.

use makapix_codec::mkpx_compact;
use makapix_engine::Session;
use std::fs;
use std::path::Path;

fn main() {
    let dir = Path::new("corpus/fuzz_load_mkpx");
    let open_dir = Path::new("corpus/fuzz_mkpx_open");
    fs::create_dir_all(dir).expect("create corpus dir");
    fs::create_dir_all(open_dir).expect("create corpus dir");
    // Every plain seed up to this size also becomes a compact-envelope seed.
    const COMPACT_SEED_MAX: usize = 64 * 1024;
    let save = |name: &str, sess: &Session| {
        let bytes = sess.save_bytes();
        assert!(!bytes.is_empty(), "empty save for seed {name}");
        fs::write(dir.join(name), &bytes).expect("write seed");
        println!("wrote {name} ({} bytes)", bytes.len());
        if bytes.len() <= COMPACT_SEED_MAX {
            let compact = mkpx_compact::compress(&bytes);
            assert!(mkpx_compact::open(&compact).as_deref() == Ok(&bytes[..]), "compact seed {name}");
            fs::write(open_dir.join(name), &compact).expect("write compact seed");
        }
    };

    // 1. Minimal empty document.
    save("seed_empty.mkpx", &Session::new(8, 8));

    // 2. Multi-frame, multi-layer drawing: strokes (RLE runs), a duplicated frame
    //    (tile-dict dedup), per-layer opacity/visibility metadata.
    let mut s = Session::new(24, 16);
    let _ = s.run_script(
        "SelectTool(Pencil)\nPointerDown(1,1)\nPointerMove(20,12)\nPointerUp()\n\
         AddLayer()\nSetPrimaryColor(#FF3B30FF)\nSelectTool(Brush)\nSetBrushSize(3)\n\
         PointerDown(5,5)\nPointerMove(12,9)\nPointerUp()\n\
         SetLayerOpacity(1,128)\nAddFrame()\nDuplicateFrame(0)\n\
         SetFrameDuration(1,200)",
    );
    save("seed_drawing.mkpx", &s);

    // 2b. The same drawing carrying provenance: a META chunk with string entries, as a
    //     Club edit/remix source does (`io::read_meta_str` is on that path).
    let with_meta = makapix_engine::io::splice_meta_str(
        &s.save_bytes(),
        &[("app", "makapix-fuzz"), ("source_post", "0123456789abcdef"), ("empty", "")],
    )
    .expect("splice META");
    fs::write(dir.join("seed_meta.mkpx"), &with_meta).expect("write seed");
    fs::write(open_dir.join("seed_meta.mkpx"), mkpx_compact::compress(&with_meta)).expect("write seed");
    println!("wrote seed_meta.mkpx ({} bytes)", with_meta.len());

    // 3. Noise fill: RAW (incompressible) tiles.
    let mut s = Session::new(16, 16);
    let _ = s.run_script("SelectAll()\nFillNoise(20260825)\nSelectNone()");
    save("seed_noise.mkpx", &s);

    // 4. Palette- and blend-heavy metadata.
    let mut s = Session::new(12, 12);
    let _ = s.run_script(
        "AddPaletteColor(#102030FF)\nAddPaletteColor(#405060FF)\nAddPaletteColor(#708090FF)\n\
         NamePaletteColor(0, slate)\nNewPalette(extra)\nAddLayer()\nSetLayerBlend(1,Multiply)\n\
         SelectTool(Gradient)\nSetGradientStops(#000000FF@0,#FFFFFFFF@1)\n\
         PointerDown(0,0)\nPointerMove(11,11)\nPointerUp()",
    );
    save("seed_palette.mkpx", &s);

    // 5. A selection that survives the save (SELC chunk over a large storage plane).
    let mut s = Session::new(256, 256);
    let _ = s.run_script("SelectAll()\nInvertSelection()\nSelectTool(SelectRect)\nPointerDown(10,10)\nPointerMove(200,180)\nPointerUp()");
    save("seed_selection_big.mkpx", &s);

    // ---- Boundary seeds: the structural maxima and the memory-budget frontier ----
    // Mutants of these land ON the caps the loader must enforce (canvas 512, layers 128,
    // MAX_FRAMES 1024, MEM_*_BUDGET refusal), which random small-file mutation reaches
    // only by luck. Size is the price of covering the refusal paths.

    // 6. A large canvas with many layers, all noise (RAW tiles — no dictionary dedup).
    let mut s = Session::new(256, 256);
    for _ in 0..15 {
        let _ = s.run_script("AddLayer()\nSelectAll()\nFillNoise(20260825)\nSelectNone()");
    }
    save("seed_max_canvas_layers.mkpx", &s);

    // 7. Many frames of identical content: exercises the tile dictionary's dedup path at
    //    scale (thousands of cells collapsing to a handful of entries).
    let mut s = Session::new(64, 64);
    let _ = s.run_script("SelectAll()\nFillNoise(7)\nSelectNone()");
    for _ in 0..200 {
        let _ = s.run_script("DuplicateFrame(0)");
    }
    save("seed_many_frames.mkpx", &s);

    // 8. Deep frames with per-frame distinct content: dictionary entries scale with
    //    frames, so this is the widest index space a legal document reaches here.
    let mut s = Session::new(64, 64);
    for i in 0..60 {
        let _ = s.run_script(&format!("AddFrame()\nSelectAll()\nFillNoise({})\nSelectNone()", i * 977 + 13));
    }
    save("seed_many_distinct_frames.mkpx", &s);

    // 9. The 512x512 canvas cap (ADR 0021), sparse: strokes across the whole canvas and
    //    one filled patch, so the file stays small while the dimensions sit on the cap.
    let mut s = Session::new(512, 512);
    let _ = s.run_script(
        "SelectTool(Brush)\nSetBrushSize(5)\nStroke([(0,0),(511,511),(511,0),(0,511)])\n\
         SelectTool(SelectRect)\nPointerDown(200,200)\nPointerMove(263,263)\nPointerUp()\n\
         FillSelection()\nSelectNone()\nAddLayer()\nSelectTool(Pencil)\nStroke([(256,0),(256,511)])",
    );
    assert!(s.size() == (512, 512), "512 seed");
    save("seed_canvas_512.mkpx", &s);

    // 10. The 128-layer cap (ADR 0032): three distinct layers duplicated up to the cap
    //     (the tile dictionary dedups the copies), with per-layer metadata varied.
    let mut s = Session::new(16, 16);
    let _ = s.run_script(
        "SelectAll()\nFillNoise(128)\nSelectNone()\nAddLayer()\nSelectTool(Pencil)\n\
         Stroke([(0,0),(15,15)])\nAddLayer()\nSetLayerBlend(2,Screen)\nSetLayerOpacity(2,77)",
    );
    for i in 3..128 {
        let _ = s.run_script(&format!("DuplicateLayer({})", i % 3));
    }
    let _ = s.run_script("SetLayerVisible(64,false)\nSetLayerLocked(127,true)\nRenameLayer(100,top, with a comma)");
    assert!(s.doc.active_frame().layers.len() == 128, "128-layer seed");
    save("seed_layers_128.mkpx", &s);

    image_seeds();
}

/// A deterministic RGBA test image: a gradient with a transparent corner and a hard edge.
fn rgba(w: u32, h: u32, phase: u32) -> Vec<u8> {
    let mut out = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        for x in 0..w {
            let a = if x < w / 4 && y < h / 4 { 0 } else { 255 };
            let edge = if (x + phase) % w < w / 2 { 255 } else { 32 };
            out.extend_from_slice(&[(x * 255 / w.max(1)) as u8, (y * 255 / h.max(1)) as u8, edge, a]);
        }
    }
    out
}

/// Seeds for `fuzz_codec_import`: the target's input is a fixed header (the `Arbitrary`
/// decode of its `Input` struct: canvas w, canvas h, scale mode, anchor, as-layer, start
/// frame, then one byte for `crop: None` or one byte + four little-endian i16 for `Some`)
/// followed by the image file bytes. One small file per decoder the app imports, static
/// and animated, so mutation starts inside each format instead of having to invent one.
fn image_seeds() {
    use image::ExtendedColorType;
    let dir = Path::new("corpus/fuzz_codec_import");
    fs::create_dir_all(dir).expect("create corpus dir");

    let (w, h) = (12u32, 9u32);
    let still = rgba(w, h, 0);
    let frames: Vec<(Vec<u8>, u32)> = (0..3).map(|i| (rgba(w, h, i * 3), 80_000 + i * 40_000)).collect();

    let png = makapix_codec::encode_png(w, h, &still).expect("png");
    let webp = makapix_codec::encode_webp(w, h, &still).expect("webp");
    let webp_anim = makapix_codec::encode_animated_webp(w, h, &frames).expect("animated webp");
    let gif = makapix_codec::encode_gif(w, h, &frames).expect("gif");

    let rgb: Vec<u8> = still.chunks(4).flat_map(|p| [p[0], p[1], p[2]]).collect();
    let mut jpeg = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg, 85)
        .encode(&rgb, w, h, ExtendedColorType::Rgb8)
        .expect("jpeg");
    let mut bmp = Vec::new();
    image::codecs::bmp::BmpEncoder::new(&mut bmp)
        .encode(&still, w, h, ExtendedColorType::Rgba8)
        .expect("bmp");

    let mut apng = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut apng, w, h);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        enc.set_animated(frames.len() as u32, 0).expect("apng header");
        let mut wr = enc.write_header().expect("apng header");
        for (i, (data, _)) in frames.iter().enumerate() {
            wr.set_frame_delay(1 + i as u16, 10).expect("apng delay");
            wr.write_image_data(data).expect("apng frame");
        }
        wr.finish().expect("apng finish");
    }

    // canvas w-1, canvas h-1, mode (0 stretch / 1 fit / 2 crop), anchor, as_layer, start, crop.
    let plain_cfg: [u8; 7] = [31, 31, 1, 1, 0, 0, 0];
    let layer_cfg: [u8; 7] = [15, 23, 0, 0, 1, 1, 0];
    let mut crop_cfg: Vec<u8> = vec![63, 63, 2, 1, 0, 0, 1];
    for v in [2i16, 1, 8, 6] {
        crop_cfg.extend_from_slice(&v.to_le_bytes());
    }

    let files: [(&str, &[u8]); 7] = [
        ("png", &png),
        ("webp", &webp),
        ("anim.webp", &webp_anim),
        ("gif", &gif),
        ("jpg", &jpeg),
        ("bmp", &bmp),
        ("apng", &apng),
    ];
    for (ext, bytes) in files {
        let n = makapix_codec::decode(bytes).unwrap_or_else(|e| panic!("seed .{ext} does not decode: {e:?}")).len();
        for (tag, cfg) in [("fit", &plain_cfg[..]), ("layer", &layer_cfg[..]), ("crop", &crop_cfg[..])] {
            // Every format gets the plain config; the layer and crop configs ride on the
            // two formats that differ most (a still PNG, an animated GIF).
            if tag != "fit" && ext != "png" && ext != "gif" {
                continue;
            }
            let mut seed = cfg.to_vec();
            seed.extend_from_slice(bytes);
            let name = format!("seed_{tag}.{ext}");
            fs::write(dir.join(&name), &seed).expect("write image seed");
            println!("wrote {name} ({} bytes, {n} frame(s))", seed.len());
        }
    }
}
