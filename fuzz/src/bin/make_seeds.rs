//! Writes seed `.mkpx` documents into `corpus/fuzz_load_mkpx/` (run from `fuzz/`).
//!
//! The seeds aim for *format diversity*, not size: empty (INDEXED/absent tiles),
//! scripted drawings (RLE-friendly runs + tile-dict dedup across duplicated frames),
//! noise (RAW tiles), and palette/blend/opacity metadata — so the coverage-guided
//! mutator starts with every chunk type and tile encoding already in the corpus.
//! `tools/fuzz/run_fuzz.sh` runs this automatically when the corpus is empty.

use makapix_engine::Session;
use std::fs;
use std::path::Path;

fn main() {
    let dir = Path::new("corpus/fuzz_load_mkpx");
    fs::create_dir_all(dir).expect("create corpus dir");
    let save = |name: &str, sess: &Session| {
        let bytes = sess.save_bytes();
        assert!(!bytes.is_empty(), "empty save for seed {name}");
        fs::write(dir.join(name), &bytes).expect("write seed");
        println!("wrote {name} ({} bytes)", bytes.len());
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
    // Mutants of these land ON the caps the loader must enforce (canvas 256, layers 64,
    // MAX_FRAMES 1024, MEM_*_BUDGET refusal), which random small-file mutation reaches
    // only by luck. Committed size is the price of covering the refusal paths.

    // 6. Maximum canvas, maximum layers, all noise (RAW tiles — no dictionary dedup).
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
}
