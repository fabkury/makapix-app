//! Makapix Animator — the deterministic scene compositor core (`makapix-scene`). A Scene of
//! keyframed Actors over a Cast of pixel-art Props, on the fixed frame grid of ADR-0001, in
//! the self-contained `.mkps` container of ADR-0002. Sits on `makapix-engine`'s public
//! primitives (buffers, color, cleanEdge transforms, container machinery); the engine's
//! drawing core is untouched. Layers (low→high): model · eval · history · compose · io ·
//! session.
#![forbid(unsafe_code)]

pub mod eval;
pub mod history;
pub mod model;
pub mod session;

pub use model::{Scene, SceneFps};
pub use session::SceneSession;
