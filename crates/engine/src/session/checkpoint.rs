//! Replay checkpoints — COW snapshots of a quiescent [`Session`] for Journal scrubbing
//! (SPEC §28.2; docs/replay/ANALYSIS.md §3.2). The Dart replay driver re-executes a
//! drawing's Journal and takes a checkpoint every few hundred actions; a scrub seek then
//! restores the nearest checkpoint at or before the target and replays the short gap.
//!
//! Everything captured here is replay-visible session state. Open gestures and pending
//! drafts are deliberately NOT captured: [`Session::is_quiescent`] gates the take, and the
//! driver simply retries at the next journal line. Restore therefore resets that transient
//! state to its defaults, exactly as it was at take time.
//!
//! Memory: snapshots are COW (frame vectors share tile `Arc`s), measured at ~0.12 MiB per
//! checkpoint on a 150k-action corpus. The store still enforces a byte budget with
//! eviction (the history-budget pattern) so adversarial content cannot pin
//! `checkpoints × document` bytes against the ~1 GiB Android allocator wall.

use std::collections::HashSet;
use std::sync::Arc;

use super::{LastGradient, Session};
use crate::buffer::RgbaBuffer;
use crate::document::Document;
use crate::geom::Point;
use crate::selection::CombineMode;
use crate::tool::{ToolKind, ToolSettings};
use crate::util::{SeededRng, VirtualClock};

/// Default retained-bytes budget for the checkpoint store. ANALYSIS §3.2 measured 35.9 MiB
/// for 300 checkpoints over the epic corpus; 48 MiB gives headroom for palettes + history
/// marginals while keeping the engine worst case (320 MiB document + 96 MiB history +
/// 48 MiB checkpoints) well under half the Android allocator wall.
pub const CHECKPOINT_BYTE_BUDGET: usize = 48 * 1024 * 1024;

/// Hard cap on live checkpoints — bounds per-entry fixed overhead and sizes the FFI ids
/// buffer contract (`mkpx_checkpoint_ids` with cap 512 always suffices).
pub const MAX_CHECKPOINTS: usize = 512;

/// Fixed per-entry overhead charge (Vec/struct/String slop) — same spirit as history's +128.
const ENTRY_OVERHEAD: usize = 4096;

/// One tile's pixel payload (32×32×4) — the same private constant io.rs and probe.rs keep.
const TILE_BYTES: usize = 4096;

/// Everything replay-visible about a quiescent session at one journal position.
struct Checkpoint {
    doc: Document, // via Document::checkpoint_clone (COW frames, deep palettes, cloned history)
    tool: ToolKind,
    settings: ToolSettings,
    selection_mode: CombineMode,
    layer_sel: Vec<usize>,
    cursor: Point,
    clipboard: Option<(RgbaBuffer, Point)>,
    rng: SeededRng, // private state — clonable only from inside the session module tree
    clock: VirtualClock,
    playing: bool,
    // Keeps the assert.gradient oracle valid after a restore; tiny.
    last_gradient: LastGradient,
    mem_budget_override: Option<(usize, usize)>,
}

struct Entry {
    id: u32,
    cp: Checkpoint,
    /// Marginal doc bytes vs the predecessor entry (tiles + tables not shared with it).
    /// Recomputed against the new predecessor when an interior entry is evicted.
    /// Entry 0 charges the full budgeted census.
    doc_delta_bytes: usize,
    /// `history.retained_bytes()` at take — an absolute; the charged marginal is derived
    /// (`saturating_sub` vs the predecessor) so eviction needs no recompute for history.
    hist_bytes_abs: usize,
    /// Deep palette bytes (palettes never COW-share).
    palette_bytes: usize,
}

impl Entry {
    fn weight(&self, prev_hist_abs: usize) -> usize {
        self.doc_delta_bytes
            + self.hist_bytes_abs.saturating_sub(prev_hist_abs)
            + self.palette_bytes
            + ENTRY_OVERHEAD
    }
}

/// The per-session checkpoint store. Lives as a field on [`Session`] but is explicitly
/// carried across the `NewDocument` whole-`*self` reset (see the `NewDocument` arm in
/// `parse.rs`) — a replayed Journal can contain `NewDocument` mid-stream, and checkpoints
/// taken before it must survive so backward scrubs can restore across the reset. Any future
/// whole-session replacement must repeat that carry (regression-tested).
#[derive(Default)]
pub(super) struct CheckpointStore {
    entries: Vec<Entry>, // ascending id == take order (the driver takes in journal order)
    next_id: u32,
    byte_budget: Option<usize>, // test override; None = CHECKPOINT_BYTE_BUDGET
}

impl CheckpointStore {
    fn budget(&self) -> usize {
        self.byte_budget.unwrap_or(CHECKPOINT_BYTE_BUDGET)
    }

    /// Rolling total of entry weights (recomputed on demand — entries is small, ≤512).
    fn total_bytes(&self) -> usize {
        let mut prev_hist = 0usize;
        let mut total = 0usize;
        for e in &self.entries {
            total += e.weight(prev_hist);
            prev_hist = e.hist_bytes_abs;
        }
        total
    }

    /// Evict down to the byte budget / count cap. Never evicts the newest entry (the take
    /// contract: a just-returned id survives at least until the next take). Prefers the
    /// interior entry whose removal creates the smallest id gap (id spacing tracks journal
    /// position under the driver's fixed-stride usage contract); ties break toward the
    /// larger weight, then the smaller id. The first entry survives while affordable
    /// (cheap restore-to-chapter-start) but is evictable under real pressure.
    fn enforce_budget(&mut self) {
        loop {
            let over_bytes = self.total_bytes() > self.budget();
            let over_count = self.entries.len() > MAX_CHECKPOINTS;
            if (!over_bytes && !over_count) || self.entries.len() <= 1 {
                return;
            }
            let victim = if self.entries.len() > 2 {
                // Interior candidates: indices 1..len-1 (keep first while we can, never last).
                let mut best: Option<(usize, u32, usize)> = None; // (index, gap, weight)
                let mut prev_hist = self.entries[0].hist_bytes_abs;
                for i in 1..self.entries.len() - 1 {
                    let gap = self.entries[i + 1].id - self.entries[i - 1].id;
                    let w = self.entries[i].weight(prev_hist);
                    prev_hist = self.entries[i].hist_bytes_abs;
                    let better = match best {
                        None => true,
                        Some((_, bg, bw)) => gap < bg || (gap == bg && w > bw),
                    };
                    if better {
                        best = Some((i, gap, w));
                    }
                }
                best.map(|(i, _, _)| i).unwrap_or(0)
            } else {
                0 // only {first, last} remain: evict the first
            };
            self.entries.remove(victim);
            // Recompute the successor's doc delta against its new predecessor.
            if victim > 0 && victim < self.entries.len() {
                let delta = doc_delta_bytes(&self.entries[victim - 1].cp.doc, &self.entries[victim].cp.doc);
                self.entries[victim].doc_delta_bytes = delta;
            } else if victim == 0 && !self.entries.is_empty() {
                // The new first entry charges its full census.
                self.entries[0].doc_delta_bytes = self.entries[0].cp.doc.budgeted_bytes();
            }
        }
    }
}

/// Bytes `new` retains beyond `prev`: tile tables of `new` not pointer-shared with `prev`,
/// plus tiles absent from `prev`'s tile set (deduped within `new` as well). One
/// O(prev tiles + new tiles) pointer walk — the same census machinery direction as
/// `probe::mem_report`, restricted to two documents.
fn doc_delta_bytes(prev: &Document, new: &Document) -> usize {
    let mut prev_tables: HashSet<usize> = HashSet::new();
    let mut prev_tiles: HashSet<usize> = HashSet::new();
    for f in &prev.frames {
        for l in &f.layers {
            if prev_tables.insert(l.pixels.table_ptr() as usize) {
                l.pixels.visit_tile_arcs(&mut |t| {
                    prev_tiles.insert(Arc::as_ptr(t) as usize);
                });
            }
        }
    }
    let mut new_tables: HashSet<usize> = HashSet::new();
    let mut new_tiles: HashSet<usize> = HashSet::new();
    let mut bytes = 0usize;
    for f in &new.frames {
        for l in &f.layers {
            let tp = l.pixels.table_ptr() as usize;
            if prev_tables.contains(&tp) || !new_tables.insert(tp) {
                continue; // whole table shared with prev (or already counted within new)
            }
            bytes += l.pixels.tile_table_bytes();
            l.pixels.visit_tile_arcs(&mut |t| {
                let p = Arc::as_ptr(t) as usize;
                if !prev_tiles.contains(&p) && new_tiles.insert(p) {
                    bytes += TILE_BYTES;
                }
            });
        }
    }
    bytes
}

fn palette_bytes(doc: &Document) -> usize {
    doc.palettes
        .iter()
        .map(|p| {
            p.colors.len() * 4
                + p.name.len()
                + p.color_names.iter().map(|n| n.as_ref().map_or(0, |s| s.len())).sum::<usize>()
                + 64
        })
        .sum()
}

impl Session {
    /// True when no gesture or draft is open — the only moments a checkpoint may be taken,
    /// because none of the transient state below is captured. Persistent drafts
    /// (shape/paste/move/rotate/scale) are deliberately also treated as non-quiescent: the
    /// replay driver retries at the next journal line, and drafts are transient in real
    /// sessions, so checkpoint density stays fine.
    pub fn is_quiescent(&self) -> bool {
        self.stroke.is_none()
            && self.precision_before.is_none()
            && !self.pen_held
            && self.move_before.is_none() // covers move_layers/move_bbox (same lifecycle)
            && self.move_sel_before.is_none()
            && self.shape_draft.is_none() // covers shape_rotation/triangle_tip (reset on commit/cancel)
            && self.paste_draft.is_none()
            && self.move_draft.is_none()
            && self.rotate_draft.is_none()
            && self.scale_draft.is_none()
    }

    /// Capture a checkpoint of the current (quiescent) state. Returns the checkpoint's
    /// STABLE id, or `None` when a gesture/draft is open (the caller retries at the next
    /// journal line). May evict older checkpoints to the byte budget — never the newest.
    pub fn take_checkpoint(&mut self) -> Option<u32> {
        if !self.is_quiescent() {
            return None;
        }
        let cp = Checkpoint {
            doc: self.doc.checkpoint_clone(),
            tool: self.tool,
            settings: self.settings.clone(),
            selection_mode: self.selection_mode,
            layer_sel: self.layer_sel.clone(),
            cursor: self.cursor,
            clipboard: self.clipboard.clone(),
            rng: self.rng.clone(),
            clock: self.clock,
            playing: self.playing,
            last_gradient: self.last_gradient.clone(),
            mem_budget_override: self.mem_budget_override,
        };
        let doc_delta = match self.checkpoints.entries.last() {
            Some(prev) => doc_delta_bytes(&prev.cp.doc, &cp.doc),
            None => cp.doc.budgeted_bytes(),
        };
        let entry = Entry {
            id: self.checkpoints.next_id,
            hist_bytes_abs: cp.doc.history.retained_bytes(),
            palette_bytes: palette_bytes(&cp.doc),
            doc_delta_bytes: doc_delta,
            cp,
        };
        self.checkpoints.next_id += 1;
        let id = entry.id;
        self.checkpoints.entries.push(entry);
        self.checkpoints.enforce_budget();
        Some(id)
    }

    /// Restore the session to checkpoint `id`. Returns false when the id is unknown
    /// (evicted / cleared / never taken). The checkpoint is retained — restore is
    /// repeatable (the scrub loop), and forward checkpoints stay valid because replaying
    /// forward from a restored state re-creates the exact states they captured
    /// (determinism).
    pub fn restore_checkpoint(&mut self, id: u32) -> bool {
        let idx = match self.checkpoints.entries.binary_search_by_key(&id, |e| e.id) {
            Ok(i) => i,
            Err(_) => return false,
        };
        let cp = &self.checkpoints.entries[idx].cp;
        self.doc = cp.doc.checkpoint_clone(); // Arc-bump re-clone; the snapshot stays restorable
        self.tool = cp.tool;
        self.settings = cp.settings.clone();
        self.selection_mode = cp.selection_mode;
        self.layer_sel = cp.layer_sel.clone();
        self.cursor = cp.cursor;
        self.clipboard = cp.clipboard.clone();
        self.rng = cp.rng.clone();
        self.clock = cp.clock;
        self.playing = cp.playing;
        self.last_gradient = cp.last_gradient.clone();
        self.mem_budget_override = cp.mem_budget_override;
        // Transient gesture/draft state was empty at take (quiescence) — reset to defaults.
        self.stroke = None;
        self.precision_before = None;
        self.pen_held = false;
        self.pen_pp.clear();
        self.paint_acc = 0.0;
        self.paste_draft = None;
        self.shape_draft = None;
        self.shape_rotation = 0.0;
        self.triangle_tip = 0.0;
        self.move_layers.clear();
        self.move_before = None;
        self.move_bbox = None;
        self.move_draft = None;
        self.rotate_draft = None;
        self.scale_draft = None;
        self.move_sel_before = None;
        // Memory model: recalibrate exactly (the adopt_loaded_doc precedent).
        // mem_refusals / mem_last_refusal are NOT touched — monotonic telemetry.
        self.mem_recalibrate();
        true
    }

    pub fn checkpoint_count(&self) -> usize {
        self.checkpoints.entries.len()
    }

    /// Live checkpoint ids, ascending. The driver resyncs its position→id map from this
    /// after every take (older ids may have been evicted).
    pub fn checkpoint_ids(&self) -> impl Iterator<Item = u32> + '_ {
        self.checkpoints.entries.iter().map(|e| e.id)
    }

    /// Drop every checkpoint, freeing the retained tiles (e.g. when the Replay view closes).
    pub fn clear_checkpoints(&mut self) {
        self.checkpoints.entries.clear();
    }

    /// Test/stress-lab override of [`CHECKPOINT_BYTE_BUDGET`] (mirrors
    /// `History::set_byte_budget`); `None` restores the default. Enforces immediately.
    pub fn set_checkpoint_budget(&mut self, budget: Option<usize>) {
        self.checkpoints.byte_budget = budget;
        self.checkpoints.enforce_budget();
    }

    /// Approximate retained bytes of the checkpoint store (the rolling-weight total; the
    /// `mem` probe stays the precise audit). Surfaced in `mem_json`.
    pub fn checkpoint_retained_bytes(&self) -> usize {
        self.checkpoints.total_bytes()
    }
}
