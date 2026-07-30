//! Cross-cutting SceneSession scenarios driven through the DSL (the engine scenarios.rs
//! discipline): state_json fragments, undo/redo content-hash round-trips, gesture coalescing,
//! the auto-key routing matrix, and budget refusal.

use makapix_scene::model::{TrackProp, Tween};
use makapix_scene::session::SceneAction;
use makapix_scene::SceneSession;

fn run(s: &mut SceneSession, script: &str) {
    s.run_script(script).expect("script runs");
}

#[test]
fn scene_setup_and_state_json() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "NewScene(48,32,25000); SetFrameCount(40); SetBackground(#102030FF); SetLoop(5,20)",
    );
    let j = s.state_json();
    assert!(j.contains("\"w\":48,"), "{j}");
    assert!(j.contains("\"millifps\":25000,"));
    assert!(j.contains("\"frame_cs\":4,"));
    assert!(j.contains("\"frame_count\":40,"));
    assert!(j.contains("\"loop\":[5,20],"));
    assert!(j.contains("\"background\":\"#102030FF\","));
    assert!(j.contains("\"cast\":[],"));
}

#[test]
fn place_key_evaluate() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "GenPropSolid(8,8,#FF0000FF); PlaceActorAt(1, 10, 20);\
         SetKey(1, x, 0, 10); SetKey(1, x, 24, 58); SetTween(1, x, 0, linear)",
    );
    let p = s.eval_pose(1, 12).unwrap();
    assert_eq!(p.x, 34); // halfway
    assert_eq!(p.y, 20); // base from placement
    let j = s.state_json();
    assert!(j.contains("\"selected_actor\":1,"));
    assert!(j.contains("\"src_frame\":0,"));
}

#[test]
fn undo_redo_content_hash_roundtrip() {
    let mut s = SceneSession::empty();
    run(&mut s, "GenProp(16,16,3,42); PlaceActor(1)");
    let h0 = s.scene.content_hash();
    run(&mut s, "SetKey(1, rot, 10, 90000); SetActorVisible(1, false); RenameActor(1, star)");
    let h1 = s.scene.content_hash();
    assert_ne!(h0, h1);
    run(&mut s, "Undo(); Undo(); Undo()");
    assert_eq!(s.scene.content_hash(), h0, "undo restores the pre-edit document");
    run(&mut s, "Redo(); Redo(); Redo()");
    assert_eq!(s.scene.content_hash(), h1, "redo replays it");
}

#[test]
fn remove_prop_cascades_and_undoes() {
    let mut s = SceneSession::empty();
    run(&mut s, "GenPropSolid(8,8,#00FF00FF); PlaceActor(1); PlaceActorAt(1, 2, 2)");
    assert_eq!(s.scene.actors.len(), 2);
    let h0 = s.scene.content_hash();
    run(&mut s, "RemoveProp(1)");
    assert!(s.scene.cast.is_empty());
    assert!(s.scene.actors.is_empty());
    run(&mut s, "Undo()");
    assert_eq!(s.scene.content_hash(), h0, "cascade undone in one step");
    assert_eq!(s.scene.actors.len(), 2);
}

#[test]
fn gesture_coalesces_to_one_undo_step() {
    let mut s = SceneSession::empty();
    run(&mut s, "GenPropSolid(8,8,#0000FFFF); PlaceActorAt(1, 0, 0); SetPlayhead(4)");
    let h0 = s.scene.content_hash();
    run(
        &mut s,
        "BeginGesture(); SetAtPlayhead(1, x, 10); SetAtPlayhead(1, y, 3);\
         SetAtPlayhead(1, x, 20); SetAtPlayhead(1, y, 6); EndGesture()",
    );
    let h1 = s.scene.content_hash();
    assert_ne!(h0, h1);
    run(&mut s, "Undo()");
    assert_eq!(s.scene.content_hash(), h0, "the whole drag is ONE undo step");
    run(&mut s, "Redo()");
    assert_eq!(s.scene.content_hash(), h1);
    // The final values won (latest-wins within the gesture).
    let p = s.eval_pose(1, 4).unwrap();
    assert_eq!((p.x, p.y), (20, 6));
}

#[test]
fn auto_key_routing_matrix() {
    let mut s = SceneSession::empty();
    run(&mut s, "GenPropSolid(8,8,#FFFFFFFF); PlaceActorAt(1, 0, 0); SetPlayhead(5)");
    // auto-key ON (default): SetAtPlayhead drops a key at the playhead.
    run(&mut s, "SetAtPlayhead(1, x, 42)");
    let a = s.scene.actor(1).unwrap();
    assert_eq!(a.tracks.get(TrackProp::X).keys.len(), 1);
    assert_eq!(a.tracks.get(TrackProp::X).keys[0].frame, 5);
    // auto-key OFF + keyless track: writes the base.
    run(&mut s, "SetAutoKey(false); SetAtPlayhead(1, y, 7)");
    let a = s.scene.actor(1).unwrap();
    assert!(a.tracks.get(TrackProp::Y).keys.is_empty());
    assert_eq!(a.tracks.get(TrackProp::Y).base, 7);
    // auto-key OFF + keyed track: still lands as a key (preview truth).
    run(&mut s, "SetAtPlayhead(1, x, 50)");
    let a = s.scene.actor(1).unwrap();
    assert_eq!(a.tracks.get(TrackProp::X).keys.len(), 1);
    assert_eq!(a.tracks.get(TrackProp::X).keys[0].v, 50);
}

#[test]
fn hold_only_properties_never_interpolate() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "GenProp(8,8,4,7); PlaceActor(1); SetActorMode(1, posing);\
         SetKey(1, fliph, 0, 0); SetKeyTween(1, fliph, 10, 1, easeinout);\
         SetKey(1, pose, 0, 0); SetKey(1, pose, 8, 3)",
    );
    let a = s.scene.actor(1).unwrap();
    for k in &a.tracks.get(TrackProp::FlipH).keys {
        assert_eq!(k.tween, Tween::Hold, "flip tween forced to hold");
    }
    let p5 = s.eval_pose(1, 5).unwrap();
    assert!(!p5.flip_h, "held, not interpolated");
    assert_eq!(p5.pose, 0);
    assert_eq!(s.resolved_src_frame(1, 9).unwrap(), 3, "posing resolves the pose track");
}

#[test]
fn move_actor_keys_is_one_step() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "GenPropSolid(8,8,#FF00FFFF); PlaceActorAt(1, 0, 0);\
         SetKey(1, x, 10, 1); SetKey(1, y, 10, 2); SetKey(1, rot, 10, 3000); SetKey(1, x, 20, 9)",
    );
    let h_before = s.scene.content_hash();
    run(&mut s, "MoveActorKeys(1, 10, 14)");
    let a = s.scene.actor(1).unwrap();
    assert!(a.tracks.get(TrackProp::X).key_at(14).is_some());
    assert!(a.tracks.get(TrackProp::Y).key_at(14).is_some());
    assert!(a.tracks.get(TrackProp::Rot).key_at(14).is_some());
    assert!(a.tracks.get(TrackProp::X).key_at(20).is_some(), "unrelated key untouched");
    run(&mut s, "Undo()");
    assert_eq!(s.scene.content_hash(), h_before, "the whole retime is one undo step");
}

#[test]
fn budget_refusal_leaves_scene_unchanged() {
    let mut s = SceneSession::empty();
    run(&mut s, "SetMemBudget(4096, 8192); GenPropSolid(8,8,#123456FF)");
    let h0 = s.scene.content_hash();
    let (refusals0, _) = s.mem_refusal_state();
    // A 256×256 dense prop (~256 KiB) cannot fit an 8 KiB hard budget.
    run(&mut s, "GenProp(256,256,1,1)");
    let (refusals1, last) = s.mem_refusal_state();
    assert_eq!(refusals1, refusals0 + 1, "refusal counted");
    assert!(last.unwrap().contains("memory budget"));
    assert_eq!(s.scene.content_hash(), h0, "scene unchanged");
    assert_eq!(s.scene.cast.len(), 1);
}

#[test]
fn pin_rules_one_level_only() {
    let mut s = SceneSession::empty();
    run(
        &mut s,
        "GenPropSolid(8,8,#111111FF); PlaceActor(1); PlaceActorAt(1, 1, 1); PlaceActorAt(1, 2, 2)",
    );
    run(&mut s, "SetPinTo(2, 1)"); // ok
    assert_eq!(s.scene.actor(2).unwrap().pin_to, Some(1));
    run(&mut s, "SetPinTo(3, 2)"); // parent pinned → no-op
    assert_eq!(s.scene.actor(3).unwrap().pin_to, None);
    run(&mut s, "SetPinTo(1, 3)"); // self has a child → no-op
    assert_eq!(s.scene.actor(1).unwrap().pin_to, None);
    run(&mut s, "SetPinTo(1, 1)"); // self-pin → no-op
    assert_eq!(s.scene.actor(1).unwrap().pin_to, None);
    // Removing the parent clears the child's pin, in one undo step.
    let h0 = s.scene.content_hash();
    run(&mut s, "RemoveActor(1)");
    assert_eq!(s.scene.actor(2).unwrap().pin_to, None);
    run(&mut s, "Undo()");
    assert_eq!(s.scene.content_hash(), h0);
}

#[test]
fn playback_clock_and_loop_region() {
    let mut s = SceneSession::empty();
    run(&mut s, "SetFrameCount(20); SetLoop(4,9); SetPlayhead(4); Play()");
    assert_eq!(s.current_play_frame(), 4);
    s.exec(SceneAction::AdvanceClock(80 * 3)); // 3 frames at 12.5 fps
    assert_eq!(s.current_play_frame(), 7);
    s.exec(SceneAction::AdvanceClock(80 * 4)); // wraps within [4,9]
    assert_eq!(s.current_play_frame(), 5);
    run(&mut s, "Pause()");
    assert_eq!(s.playhead, 5, "pause parks the playhead at the loop frame");
}

#[test]
fn duplicate_and_reorder() {
    let mut s = SceneSession::empty();
    run(&mut s, "GenPropSolid(8,8,#222222FF); PlaceActorAt(1, 0, 0); DuplicateActor(1)");
    assert_eq!(s.scene.actors.len(), 2);
    assert_eq!(s.scene.actors[1].name, "solid1 copy");
    let h0 = s.scene.content_hash();
    run(&mut s, "ReorderActor(0, 1)");
    assert_ne!(s.scene.content_hash(), h0);
    run(&mut s, "Undo()");
    assert_eq!(s.scene.content_hash(), h0);
}
