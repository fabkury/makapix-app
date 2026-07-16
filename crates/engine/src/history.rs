//! Undo/redo as a single global timeline with per-frame compaction (SPEC §10).
//!
//! Each [`Record`] stores **absolute** before/after content — both the document mutation (`Edit`)
//! and the selection-mask transition that accompanied it — so any old record can be dropped during
//! compaction without invalidating the others. The per-frame 128-state requirement is enforced by
//! counting content edits per frame and dropping the oldest for that frame.

use crate::buffer::TilePatch;
use crate::document::{Document, Frame};
use crate::geom::Size;
use crate::selection::Mask;
use std::collections::HashMap;
use std::sync::Arc;

pub const PER_FRAME_CAP: usize = 128;
pub const TOTAL_CAP: usize = 8192;
/// Byte budget for retained history (undo + redo), enforced by evicting the oldest undo records.
/// Count caps alone let adversarial content retain gigabytes (memlab, `docs/memlab/REPORT.md`):
/// 128 full-canvas repaints of one 256×256 layer ≈ 33.5 MB **per frame**, and structural records
/// scale with the whole document. 96 MiB keeps the engine's share well under the ~1 GiB Android
/// allocator wall with the document budget (SPEC §8.2b).
pub const HISTORY_BYTE_BUDGET: usize = 96 * 1024 * 1024;
/// Never evict below this many records, even over budget — undo must not silently vanish
/// entirely because one record is huge.
pub const MIN_RECORDS: usize = 8;

#[derive(Clone)]
pub enum Edit {
    /// A pixel edit on one layer of one frame (the common case).
    Pixels { frame_id: u32, layer_id: u32, patch: TilePatch },
    /// A within-frame structural/attribute/duration change (layer add/remove/reorder/…).
    FrameContent { frame_id: u32, before: Box<Frame>, after: Box<Frame> },
    /// A cross-frame or frame-collection change (add/remove/reorder/duplicate frame, bulk
    /// durations, cross-frame layer ops, import).
    DocStructure {
        label: String,
        before: Vec<Frame>,
        after: Vec<Frame>,
        before_active: usize,
        after_active: usize,
        before_size: Size,
        after_size: Size,
    },
    /// A pure selection change (marquee/invert/select-all/none/…) with no pixel or structural
    /// payload. The mask transition lives on the enclosing [`Record`]; this variant only marks the
    /// record so it occupies exactly one undo step.
    Selection,
}

impl Edit {
    fn frame_id(&self) -> Option<u32> {
        match self {
            Edit::Pixels { frame_id, .. } => Some(*frame_id),
            Edit::FrameContent { frame_id, .. } => Some(*frame_id),
            Edit::DocStructure { .. } | Edit::Selection => None,
        }
    }
    pub fn label(&self) -> &str {
        match self {
            Edit::Pixels { .. } => "pixels",
            Edit::FrameContent { .. } => "frame",
            Edit::DocStructure { label, .. } => label,
            Edit::Selection => "selection",
        }
    }
}

/// One undo step: a document mutation (`edit`) plus the selection-mask transition that accompanied
/// it. The masks are absolute COW snapshots (`Arc` clones): a pixel-only edit shares one `Arc` for
/// `before` and `after` (so it's a free pointer copy), and only a genuine selection change allocates
/// a new mask. Storing absolute (not relative) masks keeps the "any record is droppable during
/// compaction" invariant intact.
#[derive(Clone)]
pub struct Record {
    pub edit: Edit,
    pub sel_before: Option<Arc<Mask>>,
    pub sel_after: Option<Arc<Mask>>,
}

#[derive(Default)]
pub struct History {
    pub undo: Vec<Record>,
    pub redo: Vec<Record>,
    /// Per-frame content-edit count within the `undo` stack, kept in sync incrementally so the
    /// per-frame cap check is O(1) instead of rescanning the whole stack on every push. [audit F-16]
    counts: HashMap<u32, usize>,
    /// Rolling sum of [`weight_of`] over undo + redo. An intentional over-estimate (shared tiles
    /// counted per record); the `mem` probe stays the precise audit. Guards the byte budget.
    bytes: usize,
    /// Test/stress-lab override of [`HISTORY_BYTE_BUDGET`]; `None` = the default.
    byte_budget: Option<usize>,
}

/// Deterministic approximate retained bytes of one record, computed identically at push and
/// evict time so the rolling total stays consistent. Over-counts sharing on purpose (upper
/// bound): a patch's before+after tiles are weighed in full even when the after side is the
/// live document.
fn weight_of(rec: &Record) -> usize {
    const TILE_W: usize = 4096 + 32; // tile payload + Arc/heap overhead
    // Frame/Layer snapshot cost per layer AFTER the COW-table fix (M1): Layer struct + name
    // String + RgbaBuffer header; the table itself is Arc-shared until divergence.
    const LAYER_W: usize = 256;
    let mask = |m: &Option<Arc<Mask>>| m.as_ref().map(|m| m.memory_bytes()).unwrap_or(0);
    let edit = match &rec.edit {
        Edit::Pixels { patch, .. } => patch.len() * 2 * TILE_W,
        Edit::FrameContent { before, after, .. } => {
            (before.layers.len() + after.layers.len()) * LAYER_W
        }
        Edit::DocStructure { before, after, .. } => {
            let layers: usize =
                before.iter().chain(after.iter()).map(|f| f.layers.len()).sum();
            layers * LAYER_W + (before.len() + after.len()) * 64
        }
        Edit::Selection => 0,
    };
    edit + mask(&rec.sel_before) + mask(&rec.sel_after) + 128
}

impl History {
    pub fn new() -> Self {
        History::default()
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }
    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }

    /// Count of content edits (pixels/frame) belonging to `frame_id` in the undo stack. O(1):
    /// read from the maintained count map rather than rescanning the whole stack. [audit F-16]
    pub fn frame_depth(&self, frame_id: u32) -> usize {
        self.counts.get(&frame_id).copied().unwrap_or(0)
    }

    fn inc(&mut self, rec: &Record) {
        if let Some(fid) = rec.edit.frame_id() {
            *self.counts.entry(fid).or_insert(0) += 1;
        }
    }

    fn dec(&mut self, rec: &Record) {
        if let Some(fid) = rec.edit.frame_id() {
            if let Some(c) = self.counts.get_mut(&fid) {
                *c -= 1;
                if *c == 0 {
                    self.counts.remove(&fid);
                }
            }
        }
    }

    /// The effective byte budget (test override or the default).
    pub fn byte_budget(&self) -> usize {
        self.byte_budget.unwrap_or(HISTORY_BYTE_BUDGET)
    }

    /// Override the byte budget (tests / stress lab). `None` restores the default.
    pub fn set_byte_budget(&mut self, budget: Option<usize>) {
        self.byte_budget = budget;
        self.enforce_byte_budget();
    }

    /// Approximate retained bytes across undo + redo (see [`weight_of`]).
    pub fn retained_bytes(&self) -> usize {
        self.bytes
    }

    fn enforce_byte_budget(&mut self) {
        let budget = self.byte_budget();
        while self.bytes > budget && self.undo.len() > MIN_RECORDS {
            let removed = self.undo.remove(0);
            self.dec(&removed);
            self.bytes = self.bytes.saturating_sub(weight_of(&removed));
        }
    }

    fn push(&mut self, rec: Record) {
        // Redo records are not in `counts` but ARE in `bytes` — settle before clearing.
        for r in &self.redo {
            self.bytes = self.bytes.saturating_sub(weight_of(r));
        }
        self.redo.clear();
        let fid = rec.edit.frame_id();
        self.inc(&rec);
        self.bytes += weight_of(&rec);
        self.undo.push(rec);
        // Per-frame compaction: drop the oldest content edit for this frame past the cap.
        if let Some(fid) = fid {
            while self.counts.get(&fid).copied().unwrap_or(0) > PER_FRAME_CAP {
                if let Some(pos) = self.undo.iter().position(|r| r.edit.frame_id() == Some(fid)) {
                    let removed = self.undo.remove(pos);
                    self.dec(&removed);
                    self.bytes = self.bytes.saturating_sub(weight_of(&removed));
                } else {
                    break;
                }
            }
        }
        // Global safety cap.
        while self.undo.len() > TOTAL_CAP {
            let removed = self.undo.remove(0);
            self.dec(&removed);
            self.bytes = self.bytes.saturating_sub(weight_of(&removed));
        }
        // Byte budget (memlab M2): count caps bound records, this bounds what they retain.
        self.enforce_byte_budget();
    }
}

impl Document {
    /// The current selection as a cheap COW snapshot for a record's "after" side.
    fn sel_now(&self) -> Option<Arc<Mask>> {
        self.selection.clone()
    }

    /// Record a pixel edit produced by diffing a layer buffer against an earlier snapshot, together
    /// with the selection transition (`sel_before` → the current selection) so a move that carried
    /// the mask is undone/redone as one step.
    pub fn record_pixels(
        &mut self,
        frame_id: u32,
        layer_id: u32,
        patch: TilePatch,
        sel_before: Option<Arc<Mask>>,
    ) {
        if patch.is_empty() {
            return;
        }
        let sel_after = self.sel_now();
        self.history
            .push(Record { edit: Edit::Pixels { frame_id, layer_id, patch }, sel_before, sel_after });
    }

    /// Record a within-frame content change given before/after frame snapshots.
    pub fn record_frame_content(
        &mut self,
        frame_id: u32,
        before: Frame,
        after: Frame,
        sel_before: Option<Arc<Mask>>,
    ) {
        let sel_after = self.sel_now();
        self.history.push(Record {
            edit: Edit::FrameContent { frame_id, before: Box::new(before), after: Box::new(after) },
            sel_before,
            sel_after,
        });
    }

    /// Record a document-structure change given before/after frame-vector snapshots.
    pub fn record_doc_structure(
        &mut self,
        label: impl Into<String>,
        before: Vec<Frame>,
        before_active: usize,
        before_size: Size,
        sel_before: Option<Arc<Mask>>,
    ) {
        let after = self.frames.clone();
        let after_active = self.active_frame;
        let after_size = self.size;
        let sel_after = self.sel_now();
        self.history.push(Record {
            edit: Edit::DocStructure {
                label: label.into(),
                before,
                after,
                before_active,
                after_active,
                before_size,
                after_size,
            },
            sel_before,
            sel_after,
        });
    }

    /// Record a pure selection transition (`sel_before` → the current selection) as one undo step.
    pub fn record_selection(&mut self, sel_before: Option<Arc<Mask>>) {
        let sel_after = self.sel_now();
        self.history.push(Record { edit: Edit::Selection, sel_before, sel_after });
    }

    pub fn can_undo(&self) -> bool {
        self.history.can_undo()
    }
    pub fn can_redo(&self) -> bool {
        self.history.can_redo()
    }

    pub fn undo(&mut self) -> bool {
        let rec = match self.history.undo.pop() {
            Some(r) => r,
            None => return false,
        };
        self.history.dec(&rec); // record leaves the undo stack → moves to redo [audit F-16]
        self.apply(&rec.edit, false);
        self.selection = rec.sel_before.clone(); // restore the mask that accompanied this step
        self.history.redo.push(rec);
        true
    }

    pub fn redo(&mut self) -> bool {
        let rec = match self.history.redo.pop() {
            Some(r) => r,
            None => return false,
        };
        self.apply(&rec.edit, true);
        self.selection = rec.sel_after.clone();
        self.history.inc(&rec); // record returns to the undo stack [audit F-16]
        self.history.undo.push(rec);
        true
    }

    /// Apply an edit forward (`forward=true` → after) or backward (`forward=false` → before). The
    /// selection transition is applied by [`undo`]/[`redo`] around this call, so a pure
    /// `Edit::Selection` is a no-op here.
    fn apply(&mut self, edit: &Edit, forward: bool) {
        match edit {
            Edit::Pixels { frame_id, layer_id, patch } => {
                if let Some(fi) = self.frame_index_by_id(*frame_id) {
                    if let Some(li) = self.frames[fi].layer_index_by_id(*layer_id) {
                        let buf = &mut self.frames[fi].layers[li].pixels;
                        if forward {
                            buf.apply_after(patch);
                        } else {
                            buf.apply_before(patch);
                        }
                    }
                }
            }
            Edit::FrameContent { frame_id, before, after } => {
                if let Some(fi) = self.frame_index_by_id(*frame_id) {
                    let target = if forward { after.as_ref() } else { before.as_ref() };
                    self.frames[fi] = target.clone();
                    self.active_frame = self.active_frame.min(self.frames.len() - 1);
                }
            }
            Edit::DocStructure { before, after, before_active, after_active, before_size, after_size, .. } => {
                if forward {
                    self.frames = after.clone();
                    self.active_frame = *after_active;
                    self.size = *after_size;
                } else {
                    self.frames = before.clone();
                    self.active_frame = *before_active;
                    self.size = *before_size;
                }
                self.active_frame = self.active_frame.min(self.frames.len().saturating_sub(1));
            }
            // Selection-only step: the mask is restored by undo()/redo(); nothing else to do.
            Edit::Selection => {}
        }
    }
}
