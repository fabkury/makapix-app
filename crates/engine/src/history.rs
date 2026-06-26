//! Undo/redo as a single global timeline with per-frame compaction (SPEC §10).
//!
//! Each `Edit` stores **absolute** before/after content, so any old edit can be dropped
//! during compaction without invalidating the others. The per-frame 128-state requirement
//! is enforced by counting content edits per frame and dropping the oldest for that frame.

use crate::buffer::TilePatch;
use crate::document::{Document, Frame};
use crate::geom::Size;

pub const PER_FRAME_CAP: usize = 128;
pub const TOTAL_CAP: usize = 8192;

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
}

impl Edit {
    fn frame_id(&self) -> Option<u32> {
        match self {
            Edit::Pixels { frame_id, .. } => Some(*frame_id),
            Edit::FrameContent { frame_id, .. } => Some(*frame_id),
            Edit::DocStructure { .. } => None,
        }
    }
    pub fn label(&self) -> &str {
        match self {
            Edit::Pixels { .. } => "pixels",
            Edit::FrameContent { .. } => "frame",
            Edit::DocStructure { label, .. } => label,
        }
    }
}

#[derive(Default)]
pub struct History {
    pub undo: Vec<Edit>,
    pub redo: Vec<Edit>,
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

    /// Count of content edits (pixels/frame) belonging to `frame_id` in the undo stack.
    pub fn frame_depth(&self, frame_id: u32) -> usize {
        self.undo.iter().filter(|e| e.frame_id() == Some(frame_id)).count()
    }

    fn push(&mut self, edit: Edit) {
        self.redo.clear();
        let fid = edit.frame_id();
        self.undo.push(edit);
        // Per-frame compaction: drop the oldest content edit for this frame past the cap.
        if let Some(fid) = fid {
            while self.frame_depth(fid) > PER_FRAME_CAP {
                if let Some(pos) = self.undo.iter().position(|e| e.frame_id() == Some(fid)) {
                    self.undo.remove(pos);
                } else {
                    break;
                }
            }
        }
        // Global safety cap.
        while self.undo.len() > TOTAL_CAP {
            self.undo.remove(0);
        }
    }
}

impl Document {
    /// Record a pixel edit produced by diffing a layer buffer against an earlier snapshot.
    pub fn record_pixels(&mut self, frame_id: u32, layer_id: u32, patch: TilePatch) {
        if patch.is_empty() {
            return;
        }
        self.history.push(Edit::Pixels { frame_id, layer_id, patch });
    }

    /// Record a within-frame content change given before/after frame snapshots.
    pub fn record_frame_content(&mut self, frame_id: u32, before: Frame, after: Frame) {
        self.history
            .push(Edit::FrameContent { frame_id, before: Box::new(before), after: Box::new(after) });
    }

    /// Record a document-structure change given before/after frame-vector snapshots.
    pub fn record_doc_structure(
        &mut self,
        label: impl Into<String>,
        before: Vec<Frame>,
        before_active: usize,
        before_size: Size,
    ) {
        let after = self.frames.clone();
        let after_active = self.active_frame;
        let after_size = self.size;
        self.history.push(Edit::DocStructure {
            label: label.into(),
            before,
            after,
            before_active,
            after_active,
            before_size,
            after_size,
        });
    }

    pub fn can_undo(&self) -> bool {
        self.history.can_undo()
    }
    pub fn can_redo(&self) -> bool {
        self.history.can_redo()
    }

    pub fn undo(&mut self) -> bool {
        let edit = match self.history.undo.pop() {
            Some(e) => e,
            None => return false,
        };
        self.apply(&edit, false);
        self.history.redo.push(edit);
        true
    }

    pub fn redo(&mut self) -> bool {
        let edit = match self.history.redo.pop() {
            Some(e) => e,
            None => return false,
        };
        self.apply(&edit, true);
        self.history.undo.push(edit);
        true
    }

    /// Apply an edit forward (`forward=true` → after) or backward (`forward=false` → before).
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
        }
    }
}
