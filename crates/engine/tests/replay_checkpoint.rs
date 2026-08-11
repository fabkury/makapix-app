//! Replay-checkpoint invariants (session/checkpoint.rs): a checkpoint restore followed by
//! re-execution must be indistinguishable from a straight run — including RNG mid-state,
//! Undo() reaching pre-checkpoint history, and NewDocument whole-session resets — and the
//! byte budget must evict deterministically without ever dropping the newest checkpoint.

use makapix_engine::Session;

fn run(src: &str) -> Session {
    let mut s = Session::empty();
    s.run_script(src).expect("script ok");
    s
}

const PREFIX: &str = "NewDocument(64,64)
SetSeed(7)
SelectTool(Pencil); SetBrushSize(3); SetPrimaryColor(#D04648FF)
Stroke([(4,4),(30,20),(50,9)])
SelectTool(Bucket); Tap(60,60)
SelectTool(Pencil); SetPrimaryColor(#30346DFF)
Stroke([(10,50),(40,44)])
";

const SUFFIX: &str = "SelectTool(Brush); SetBrushSize(5); SetPrimaryColor(#6DAA2CFF)
Stroke([(20,20),(44,52)])
AddLayer()
SelectTool(Pencil); SetPrimaryColor(#DEEED6FF)
Stroke([(2,2),(12,3)])
DuplicateFrame(0)
SetActiveFrame(1)
Stroke([(30,30),(33,40)])
";

/// Fingerprint = content hash + the full state JSON (the hash excludes palettes /
/// active_frame / selection; state_json covers them).
fn fingerprint(s: &mut Session) -> (String, String) {
    (
        makapix_engine::util::hash_hex(s.doc.content_hash()),
        s.state_json(),
    )
}

#[test]
fn checkpoint_restore_is_deterministic() {
    let mut s = run(PREFIX);
    let id = s.take_checkpoint().expect("quiescent after prefix");
    s.run_script(SUFFIX).unwrap();
    let straight = fingerprint(&mut s);

    assert!(s.restore_checkpoint(id));
    s.run_script(SUFFIX).unwrap();
    let replayed = fingerprint(&mut s);
    assert_eq!(straight, replayed, "restore + suffix must equal straight run");

    let mut fresh = run(&format!("{PREFIX}{SUFFIX}"));
    let fresh_fp = fingerprint(&mut fresh);
    assert_eq!(straight, fresh_fp, "one-shot run must equal checkpointed run");
}

#[test]
fn rng_state_survives_restore() {
    // The checkpoint must capture the rng's MID-STREAM state, not just the seed: the prefix
    // consumes randomness (an airbrush tap) after SetSeed.
    let prefix = "NewDocument(64,64)
SetSeed(42)
SelectTool(Airbrush); SetBrushSize(4); SetIntensity(220); SetPrimaryColor(#D27D2CFF)
Tap(16,16)
";
    let suffix = "Tap(32,32)
Tap(48,16)
";
    let mut s = run(prefix);
    let id = s.take_checkpoint().unwrap();
    s.run_script(suffix).unwrap();
    let straight = s.doc.content_hash();

    assert!(s.restore_checkpoint(id));
    s.run_script(suffix).unwrap();
    assert_eq!(straight, s.doc.content_hash(), "airbrush after restore must reuse the exact rng state");
}

#[test]
fn history_survives_restore() {
    // The suffix undoes PAST the checkpoint boundary (2 edits after, 3 undos) — only a
    // cloned history can serve the third Undo. Then redo + a new stroke.
    let suffix = "SelectTool(Pencil); SetPrimaryColor(#8595A1FF)
Stroke([(5,40),(20,40)])
Stroke([(5,44),(20,44)])
Undo()
Undo()
Undo()
Redo()
Stroke([(5,48),(20,48)])
";
    let mut s = run(PREFIX);
    let id = s.take_checkpoint().unwrap();
    s.run_script(suffix).unwrap();
    let straight = fingerprint(&mut s);

    assert!(s.restore_checkpoint(id));
    s.run_script(suffix).unwrap();
    assert_eq!(straight, fingerprint(&mut s), "Undo() reaching pre-checkpoint records must replay identically");
}

#[test]
fn take_refused_mid_gesture() {
    let mut s = run(PREFIX);
    assert!(s.is_quiescent());

    // Open pointer stroke.
    s.run_script("PointerDown(10,10)\nPointerMove(12,12)").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("PointerUp()").unwrap();
    assert!(s.take_checkpoint().is_some());

    // Precision pen held.
    s.run_script("CursorPenDown()").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("CursorPenUp()").unwrap();
    assert!(s.take_checkpoint().is_some());

    // Shape draft.
    s.run_script("SelectTool(Rectangle)\nShapeSet(2,2,20,20)").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("ShapeCancel()").unwrap();
    assert!(s.take_checkpoint().is_some());

    // Paste draft.
    s.run_script("SelectAll()\nCopy()\nSelectTool(CopyPaste)\nPasteDraft()").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("PasteCancel()").unwrap();
    assert!(s.take_checkpoint().is_some());

    // Selection-mask drag.
    s.run_script("MoveSelectionBegin()").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("MoveSelectionCommit()").unwrap();
    assert!(s.take_checkpoint().is_some());

    // Move draft (whole layer — no selection needed).
    s.run_script("SelectNone()\nMoveDraftBegin()").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("MoveDraftCancel()").unwrap();
    assert!(s.take_checkpoint().is_some());

    // Rotate + scale drafts.
    s.run_script("RotateDraftBegin()").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("RotateDraftCancel()").unwrap();
    s.run_script("ScaleDraftBegin()").unwrap();
    assert!(s.take_checkpoint().is_none());
    s.run_script("ScaleDraftCancel()").unwrap();
    assert!(s.take_checkpoint().is_some());
}

#[test]
fn newdocument_carries_store() {
    let mut s = run(PREFIX);
    let pre_reset_hash = s.doc.content_hash();
    let a = s.take_checkpoint().unwrap();

    s.run_script("NewDocument(32,32)\nSelectTool(Pencil); SetPrimaryColor(#DAD45EFF)\nStroke([(1,1),(10,10)])").unwrap();
    assert!(s.checkpoint_count() >= 1, "the store must survive the whole-session reset");
    let post_reset_hash = s.doc.content_hash();
    let b = s.take_checkpoint().unwrap();

    // Backward across the reset.
    assert!(s.restore_checkpoint(a));
    assert_eq!(s.doc.content_hash(), pre_reset_hash);
    assert!(s.state_json().contains("\"size\":[64,64]"));
    // Forward across the reset.
    assert!(s.restore_checkpoint(b));
    assert_eq!(s.doc.content_hash(), post_reset_hash);
    assert!(s.state_json().contains("\"size\":[32,32]"));
}

#[test]
fn budget_eviction_keeps_last_and_is_bounded() {
    let mut s = run("NewDocument(64,64)");
    s.set_checkpoint_budget(Some(300_000));
    let mut taken: Vec<u32> = Vec::new();
    for seed in 0..12u32 {
        s.run_script(&format!("FillNoise({seed})")).unwrap();
        taken.push(s.take_checkpoint().expect("quiescent"));
        let live: Vec<u32> = s.checkpoint_ids().collect();
        assert!(live.contains(taken.last().unwrap()), "newest id must always survive");
        assert!(live.windows(2).all(|w| w[0] < w[1]), "ids stay ascending");
    }
    assert!(s.checkpoint_count() < 12, "the tiny budget must have evicted");
    assert!(
        s.checkpoint_retained_bytes() <= 300_000 || s.checkpoint_count() == 1,
        "retained bytes obey the budget (down to the 1-entry floor)"
    );
    let live: Vec<u32> = s.checkpoint_ids().collect();
    let evicted = taken.iter().find(|id| !live.contains(id)).expect("some id was evicted");
    assert!(!s.restore_checkpoint(*evicted), "an evicted id must not restore");
    // Live ones all restore.
    for id in live {
        assert!(s.restore_checkpoint(id));
    }
}

#[test]
fn restore_is_repeatable() {
    let mut s = run(PREFIX);
    let id = s.take_checkpoint().unwrap();
    s.run_script(SUFFIX).unwrap();
    assert!(s.restore_checkpoint(id));
    s.run_script(SUFFIX).unwrap();
    let first = fingerprint(&mut s);
    assert!(s.restore_checkpoint(id));
    s.run_script(SUFFIX).unwrap();
    assert_eq!(first, fingerprint(&mut s), "the same checkpoint restores identically twice");
}

#[test]
fn editor_state_is_captured() {
    // Clipboard + cursor + selection travel with the checkpoint: a Paste() and a
    // PlotCursor() after restore must reproduce the straight run exactly.
    let prefix = "NewDocument(64,64)
SelectTool(Pencil); SetBrushSize(1); SetPrimaryColor(#D04648FF)
Stroke([(2,2),(9,9)])
SelectAll()
Copy()
SelectNone()
SetCursor(40,40)
";
    let suffix = "Paste()
PlotCursor()
";
    let mut s = run(prefix);
    let id = s.take_checkpoint().unwrap();
    s.run_script(suffix).unwrap();
    let straight = fingerprint(&mut s);
    assert!(s.restore_checkpoint(id));
    s.run_script(suffix).unwrap();
    assert_eq!(straight, fingerprint(&mut s));
}

#[test]
fn mem_model_after_restore() {
    // A tiny hard budget: the second noise fill is refused (rolled back). After a restore,
    // the refusal counter must not regress and the budget gate must still hold exactly.
    let mut s = run("NewDocument(64,64)\nSetMemBudget(4096,8192)");
    let id = s.take_checkpoint().unwrap();
    s.run_script("FillNoise(1)").unwrap(); // a 64×64 canvas fill ≈ 4 tiles ≈ 16 KB > hard → refused
    let (refusals_before, _) = s.mem_refusal_state();
    assert!(refusals_before > 0, "the over-budget fill must be refused");
    assert!(s.restore_checkpoint(id));
    let (refusals_after, _) = s.mem_refusal_state();
    assert!(refusals_after >= refusals_before, "refusal telemetry is monotonic across restores");
    s.run_script("FillNoise(2)").unwrap();
    let (refusals_final, _) = s.mem_refusal_state();
    assert!(refusals_final > refusals_after, "the budget gate still refuses after a restore (recalibrated)");
}

#[test]
fn clear_checkpoints_frees() {
    let mut s = run(PREFIX);
    let a = s.take_checkpoint().unwrap();
    s.run_script("FillNoise(3)").unwrap();
    let b = s.take_checkpoint().unwrap();
    assert_eq!(s.checkpoint_count(), 2);
    s.clear_checkpoints();
    assert_eq!(s.checkpoint_count(), 0);
    assert!(!s.restore_checkpoint(a));
    assert!(!s.restore_checkpoint(b));
    assert!(s.mem_json().contains("\"checkpoints\":{\"count\":0"));
}
