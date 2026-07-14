//! Makapix engine — pure, deterministic, headless core (SPEC §4).
//!
//! Layers (low→high): util · geom · color · buffer/raster/selection · document ·
//! history · tool · render · probe · io · session. The `Session` is the single stateful
//! entry point for the CLI harness and the Flutter shell.
#![forbid(unsafe_code)]

pub mod buffer;
pub mod cleanedge;
pub mod color;
pub mod document;
pub mod geom;
pub mod history;
pub mod import;
pub mod io;
pub mod probe;
pub mod raster;
pub mod render;
pub mod selection;
pub mod session;
pub mod tool;
pub mod util;

pub use color::Rgba8;
pub use document::Document;
pub use session::Session;
