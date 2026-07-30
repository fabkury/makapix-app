//! Informational compositor timing (the engine perf.rs pattern): prints cold/warm
//! `scene_frame` times at the ceiling configuration. Not a hard gate — the 16 ms on-device
//! measurement belongs to the Flutter phase — but a regression here is an early smell.
//! Run with `cargo test -p makapix-scene --test perf -- --nocapture`.

use makapix_scene::compose::{scene_frame, TransformCache, TRANSFORM_CACHE_BUDGET};
use makapix_scene::SceneSession;
use std::time::Instant;

#[test]
fn ceiling_composite_timing() {
    let mut s = SceneSession::empty();
    s.run_script("NewScene(256,256,25000)").unwrap();
    // 16 props × 4 actors each = the 64-actor ceiling, all rotated + scaled + cleanEdge.
    for p in 1..=16u32 {
        s.run_script(&format!("GenProp(24,24,2,{p}); SetPropStyle({p}, cleanedge)")).unwrap();
        for a in 0..4 {
            let x = (p * 15) % 250;
            let y = (a * 60 + p) % 250;
            s.run_script(&format!("PlaceActorAt({p}, {x}, {y})")).unwrap();
        }
    }
    let n = s.scene.actors.len() as u32;
    for id in 1..=n {
        s.run_script(&format!(
            "SetKey({id}, rot, 0, {}); SetKey({id}, rot, 40, {}); SetKey({id}, scale, 0, 1500)",
            (id * 13_000) % 360_000,
            (id * 29_000) % 360_000
        ))
        .unwrap();
    }

    let t0 = Instant::now();
    let mut cold_cache = TransformCache::new(TRANSFORM_CACHE_BUDGET);
    let img = scene_frame(&s.scene, &mut cold_cache, 7);
    let cold = t0.elapsed();
    let t1 = Instant::now();
    let img2 = scene_frame(&s.scene, &mut cold_cache, 7);
    let warm = t1.elapsed();
    assert_eq!(img.content_hash(), img2.content_hash());
    println!(
        "# perf scene_frame 256x256, {} actors (cleanEdge, rot+scale): cold={:?} warm={:?} cache={} KiB",
        n,
        cold,
        warm,
        cold_cache.bytes() / 1024
    );
}
