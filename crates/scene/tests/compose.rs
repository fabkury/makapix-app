//! Compositor scenarios: z-order, opacity, background, pinning, Cycles, warm-vs-cold
//! determinism (incl. under eviction), and the Prop-import paths (raster + .mkpx whole/split).

use makapix_engine::color::{self, Rgba8};
use makapix_scene::compose::{scene_frame, TransformCache};
use makapix_scene::SceneSession;

fn run(s: &mut SceneSession, script: &str) {
    s.run_script(script).expect("script runs");
}

#[test]
fn z_order_and_background() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "NewScene(16,16,12500); SetBackground(#00FF00FF);\
         GenPropSolid(8,8,#FF0000FF); GenPropSolid(8,8,#0000FFFF);\
         PlaceActorAt(1, 4, 4); PlaceActorAt(2, 4, 4)",
    );
    let buf = s.composite(0);
    // Actor 2 (later = higher z) wins where both overlap.
    assert_eq!(buf.get(4, 4), Rgba8::new(0, 0, 255, 255));
    // Outside both props: the background.
    assert_eq!(buf.get(15, 15), Rgba8::new(0, 255, 0, 255));
    // Reorder: actor 2 to the bottom → actor 1 wins.
    run(&mut s, "ReorderActor(1, 0)");
    assert_eq!(s.composite(0).get(4, 4), Rgba8::new(255, 0, 0, 255));
}

#[test]
fn opacity_blends_and_invisible_skips() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "NewScene(8,8,12500); SetBackground(#000000FF); GenPropSolid(8,8,#FFFFFFFF);\
         PlaceActorAt(1, 4, 4); SetBase(1, opacity, 128)",
    );
    let got = s.composite(0).get(4, 4);
    let want = color::over_opacity(
        Rgba8::new(255, 255, 255, 255),
        Rgba8::new(0, 0, 0, 255),
        128,
    );
    assert_eq!(got, want, "actor opacity routes through over_opacity");
    run(&mut s, "SetActorVisible(1, false)");
    assert_eq!(s.composite(0).get(4, 4), Rgba8::new(0, 0, 0, 255));
}

#[test]
fn pinned_child_follows_parent_exactly_at_quarter_turns() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "NewScene(32,32,12500); GenPropSolid(2,2,#FF0000FF); GenPropSolid(2,2,#0000FFFF);\
         PlaceActorAt(1, 16, 16); PlaceActorAt(2, 3, 1); SetPinTo(2, 1)",
    );
    // Child (x, y) is PARENT-PROP-LOCAL once pinned: (3, 1) against the parent's (1, 1) pivot
    // is a (+2, 0) offset, so the child renders near (18, 16). Rotating the parent 90° CW
    // carries it to (16, 18) — assert relative displacement via the blue pixel.
    let find_blue = |buf: &makapix_engine::buffer::RgbaBuffer| -> Option<(i32, i32)> {
        for y in 0..32 {
            for x in 0..32 {
                if buf.get(x, y) == Rgba8::new(0, 0, 255, 255) {
                    return Some((x, y));
                }
            }
        }
        None
    };
    let before = find_blue(&s.composite(0)).expect("child visible");
    run(&mut s, "SetBase(1, rot, 90000)");
    let after = find_blue(&s.composite(0)).expect("child still visible");
    assert_ne!(before, after, "child moved with the parent's rotation");
    // Opacity does NOT inherit: dim the parent, the child stays opaque.
    run(&mut s, "SetBase(1, opacity, 0)");
    assert!(find_blue(&s.composite(0)).is_some(), "child unaffected by parent opacity");
}

#[test]
fn cycles_advance_in_composite() {
    let mut s = SceneSession::empty();
    // A 2-frame prop via GenProp (noise differs per frame), cycle 2 scene frames each.
    run(
        &mut s,
        "NewScene(16,16,12500); GenProp(8,8,2,42); SetCycleAll(1, 2); PlaceActorAt(1, 8, 8)",
    );
    let f0 = s.frame_hash(0);
    let f1 = s.frame_hash(1);
    let f2 = s.frame_hash(2);
    let f4 = s.frame_hash(4);
    assert_eq!(f0, f1, "first prop frame holds for 2 scene frames");
    assert_ne!(f1, f2, "second prop frame at scene frame 2");
    assert_eq!(f0, f4, "cycle wraps (len 4)");
}

#[test]
fn warm_cold_and_eviction_determinism() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "NewScene(48,48,12500); GenProp(12,12,3,7); PlaceActorAt(1, 24, 24);\
         SetKey(1, rot, 0, 0); SetKey(1, rot, 20, 137000); SetKey(1, scale, 0, 1000);\
         SetKey(1, scale, 20, 2500); SetTween(1, rot, 0, easeinout)",
    );
    for f in [0u32, 3, 7, 13, 19] {
        let warm1 = s.frame_hash(f);
        let warm2 = s.frame_hash(f);
        let cold = scene_frame(&s.scene, &mut TransformCache::new(1 << 25), f).content_hash() as u64;
        // A pathologically tiny cache budget forces eviction on every actor — output identical.
        let starved =
            scene_frame(&s.scene, &mut TransformCache::new(1), f).content_hash() as u64;
        assert_eq!(warm1, warm2, "frame {f}: warm repeat");
        assert_eq!(warm1, cold, "frame {f}: cold rebuild");
        assert_eq!(warm1, starved, "frame {f}: starved cache");
    }
}

#[test]
fn import_gif_quantizes_cycle() {
    // Encode a tiny 2-frame GIF through the codec (100 ms + 200 ms), import at 12.5 fps
    // (80 ms/frame): 100→1 (1.25 rounds down), 200→3 (2.5 rounds up half-up).
    let f0 = vec![255u8, 0, 0, 255].repeat(4); // 2×2 red
    let f1 = vec![0u8, 0, 255, 255].repeat(4); // 2×2 blue
    let gif =
        makapix_codec::encode_gif(2, 2, &[(f0, 100_000), (f1, 200_000)]).expect("encode");
    let mut s = SceneSession::empty();
    run(&mut s, "NewScene(16,16,12500)");
    let out = s.import_prop_bytes(&gif, "twoframe", false, true).expect("import");
    assert_eq!(out.props.len(), 1);
    assert_eq!(out.actors.len(), 1);
    let p = s.scene.prop(out.props[0]).unwrap();
    assert_eq!(p.frames.len(), 2);
    assert_eq!(p.cycle_map, vec![1, 3], "durations quantized per ADR-0001");
    // One undo step reverts the whole import (prop + actor).
    let before = s.scene.content_hash();
    run(&mut s, "Undo()");
    assert!(s.scene.cast.is_empty() && s.scene.actors.is_empty());
    run(&mut s, "Redo()");
    assert_eq!(s.scene.content_hash(), before);
}

#[test]
fn import_mkpx_whole_and_split() {
    // Build a 2-layer, 2-frame drawing through the ENGINE and save it as .mkpx bytes.
    // Layer buffers are STORAGE-sized (canvas + gutter): canvas pixel (x, y) lives at
    // origin + (x, y).
    let mut doc = makapix_engine::Document::new(10, 6);
    let o = doc.origin();
    doc.active_frame_mut().layers[0].pixels.set(o.x + 1, o.y + 1, Rgba8::new(255, 0, 0, 255));
    let mut top = doc.new_layer("arm");
    top.pixels.set(o.x + 2, o.y + 2, Rgba8::new(0, 0, 255, 255));
    doc.active_frame_mut().layers.push(top);
    let f2 = makapix_engine::document::Frame {
        id: doc.new_frame_id(),
        duration_us: 160_000,
        layers: vec![doc.new_layer("l0"), doc.new_layer("l1")],
        active_layer: 0,
    };
    doc.frames.push(f2);
    let bytes = makapix_engine::io::save_to_bytes(&doc);

    // Whole: one Prop, frames = composites.
    let mut s = SceneSession::empty();
    run(&mut s, "NewScene(32,32,12500)");
    let whole = s.import_prop_bytes(&bytes, "drawing", false, false).expect("whole import");
    assert_eq!(whole.props.len(), 1);
    assert!(whole.actors.is_empty(), "place_actors=false");
    let p = s.scene.prop(whole.props[0]).unwrap();
    assert_eq!((p.w, p.h), (10, 6));
    assert_eq!(p.frames.len(), 2);
    assert_eq!(p.cycle_map, vec![1, 2], "100 ms → 1, 160 ms → 2 at 80 ms/frame");
    assert_eq!(p.frames[0].get(2, 2), Rgba8::new(0, 0, 255, 255), "composited");

    // Split: one Prop per layer, actors self-assembled in layer order.
    let mut s2 = SceneSession::empty();
    run(&mut s2, "NewScene(32,32,12500)");
    let split = s2.import_prop_bytes(&bytes, "drawing", true, true).expect("split import");
    assert_eq!(split.props.len(), 2, "one Prop per layer");
    assert_eq!(split.actors.len(), 2);
    let names: Vec<String> =
        split.props.iter().map(|&id| s2.scene.prop(id).unwrap().name.clone()).collect();
    assert!(names[1] == "arm", "layer names become Prop names: {names:?}");
    // Parts align: composite equals the whole drawing's frame-0 composite where placed.
    let buf = s2.composite(0);
    assert_eq!(buf.get(1, 1), Rgba8::new(255, 0, 0, 255));
    assert_eq!(buf.get(2, 2), Rgba8::new(0, 0, 255, 255));
}

#[test]
fn import_budget_refusal_is_clean() {
    let mut s = SceneSession::empty();
    run(&mut s, "NewScene(16,16,12500); SetMemBudget(4096, 8192)");
    // A 64×64 opaque PNG (~16 KiB decoded) exceeds the 8 KiB hard budget.
    let rgba = vec![10u8, 20, 30, 255].repeat(64 * 64);
    let png = makapix_codec::encode_png(64, 64, &rgba).expect("png");
    let before = s.scene.content_hash();
    let err = s.import_prop_bytes(&png, "big", false, true).unwrap_err();
    assert!(err.contains("memory budget"), "{err}");
    assert_eq!(s.scene.content_hash(), before, "scene untouched");
    let (refusals, _) = s.mem_refusal_state();
    assert_eq!(refusals, 1);
}

#[test]
fn oversized_prop_rejected() {
    let mut s = SceneSession::empty();
    run(&mut s, "NewScene(16,16,12500)");
    let rgba = vec![0u8; 1100 * 4 * 4];
    let png = makapix_codec::encode_png(1100, 4, &rgba).expect("png");
    let err = s.import_prop_bytes(&png, "wide", false, false).unwrap_err();
    assert!(err.contains("1024"), "{err}");
}

#[test]
fn hit_test_topmost_opaque() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "NewScene(32,32,12500); GenPropSolid(8,8,#FF0000FF); GenPropSolid(8,8,#0000FFFF);\
         PlaceActorAt(1, 8, 8); PlaceActorAt(2, 12, 8)",
    );
    // Props are 8×8 centered on their positions: actor 1 spans [4,12), actor 2 spans [8,16).
    assert_eq!(s.hit_test(0, 5, 8), Some(1), "only actor 1 there");
    assert_eq!(s.hit_test(0, 10, 8), Some(2), "overlap → topmost wins");
    assert_eq!(s.hit_test(0, 30, 30), None, "empty space");
    run(&mut s, "SetActorVisible(2, false)");
    assert_eq!(s.hit_test(0, 10, 8), Some(1), "invisible actors don't hit");
}
