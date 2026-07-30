//! Hostile-input fuzzing (the engine fuzz_inputs.rs pattern): deterministic pseudo-random DSL
//! scripts thrown at a `SceneSession` — every action must clamp or no-op; nothing may panic.

use makapix_engine::util::SeededRng;
use makapix_scene::SceneSession;

const VERBS: &[&str] = &[
    "NewScene({a},{b},12500)",
    "SetFps({a})",
    "SetFrameCount({a})",
    "SetBackground(#12345678)",
    "SetLoop({a},{b})",
    "GenPropSolid({a},{b},#FF00FFFF)",
    "GenProp(9,9,{a},{b})",
    "RemoveProp({a})",
    "RenameProp({a},zz)",
    "SetPropStyle({a},cleanedge)",
    "SetCycleStep({a},{b},{c})",
    "SetCycleAll({a},{c})",
    "PlaceActor({a})",
    "PlaceActorAt({a},{sa},{sb})",
    "DuplicateActor({a})",
    "RemoveActor({a})",
    "SelectActor({a})",
    "SelectNone()",
    "SetActorMode({a},posing)",
    "SetPinTo({a},{b})",
    "ClearPin({a})",
    "ReorderActor({a},{b})",
    "SetActorVisible({a},true)",
    "SetBase({a},x,{sa})",
    "SetKey({a},rot,{b},{sa})",
    "SetKeyTween({a},scale,{b},{sa},easein)",
    "RemoveKey({a},x,{b})",
    "MoveKey({a},x,{b},{c})",
    "MoveActorKeys({a},{b},{c})",
    "SetTween({a},x,{b},easeout)",
    "ClearTrack({a},opacity)",
    "SetAtPlayhead({a},y,{sa})",
    "BeginGesture()",
    "EndGesture()",
    "SetPlayhead({a})",
    "SetAutoKey(true)",
    "Play()",
    "Pause()",
    "AdvanceClock({a})",
    "Undo()",
    "Redo()",
    "ClearHistory()",
];

#[test]
fn hostile_scripts_never_panic() {
    let mut rng = SeededRng::new(0xF00D);
    for round in 0..40 {
        let mut s = SceneSession::empty();
        let mut script = String::new();
        for _ in 0..120 {
            let verb = VERBS[(rng.next_u64() % VERBS.len() as u64) as usize];
            let a = rng.next_u64() % 3000;
            let b = rng.next_u64() % 3000;
            let c = rng.next_u64() % 3000;
            let sa = (rng.next_u64() % 200_000) as i64 - 100_000;
            let sb = (rng.next_u64() % 200_000) as i64 - 100_000;
            let line = verb
                .replace("{a}", &a.to_string())
                .replace("{b}", &b.to_string())
                .replace("{c}", &c.to_string())
                .replace("{sa}", &sa.to_string())
                .replace("{sb}", &sb.to_string());
            script.push_str(&line);
            script.push('\n');
        }
        // Parse errors are fine (bad enum tokens never occur above, but ranges may reject);
        // panics are the failure. Execute line-by-line so one parse error doesn't stop the round.
        for line in script.lines() {
            let _ = s.run_script(line);
        }
        // The session must still be coherent enough to serve state.
        let j = s.state_json();
        assert!(j.starts_with('{') && j.ends_with('}'), "round {round}: state_json intact");
    }
}
