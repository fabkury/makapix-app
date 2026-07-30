//! The Animator action-script DSL: `Name(args)` lines (the engine parser's grammar — `;`
//! separators, `#`/`//` comments, typed accessors, non-finite rejection), one variant per
//! editing capability. Verbs are the seam contract with the shell (docs/animator plan §Seam);
//! every exec path clamps or no-ops — never panics.

use crate::model::{ActorMode, PixelStyle, TrackProp, Tween};
use crate::session::SceneSession;
use makapix_engine::color::Rgba8;

#[derive(Clone, Debug, PartialEq)]
pub enum SceneAction {
    // scene setup
    NewScene(u16, u16, u32), // w, h, millifps
    SetFps(u32),
    SetFrameCount(u32),
    SetBackground(Rgba8),
    SetLoop(u32, u32),
    // cast
    GenProp(u32, u32, u32, u64), // w, h, frames, seed — seeded noise (tests/CLI)
    GenPropSolid(u32, u32, Rgba8), // 1-frame solid prop (readable goldens)
    RemoveProp(u32),
    RenameProp(u32, String),
    SetPropStyle(u32, PixelStyle),
    SetCycleStep(u32, u32, u16), // prop, prop_frame_idx, steps
    SetCycleAll(u32, u16),
    // actors
    PlaceActor(u32),
    PlaceActorAt(u32, i32, i32),
    DuplicateActor(u32),
    RemoveActor(u32),
    RenameActor(u32, String),
    SelectActor(u32),
    SelectNone,
    SetActorMode(u32, ActorMode),
    SetPinTo(u32, u32),
    ClearPin(u32),
    ReorderActor(usize, usize),
    SetActorVisible(u32, bool),
    // values & keys
    SetBase(u32, TrackProp, i64),
    SetKey(u32, TrackProp, u32, i64),
    SetKeyTween(u32, TrackProp, u32, i64, Tween),
    RemoveKey(u32, TrackProp, u32),
    MoveKey(u32, TrackProp, u32, u32),
    MoveActorKeys(u32, u32, u32),
    SetTween(u32, TrackProp, u32, Tween),
    ClearTrack(u32, TrackProp),
    SetAtPlayhead(u32, TrackProp, i64),
    BeginGesture,
    EndGesture,
    // playhead & review
    SetPlayhead(u32),
    SetAutoKey(bool),
    Play,
    Pause,
    AdvanceClock(u64), // ms
    // history & budgets
    Undo,
    Redo,
    ClearHistory,
    SetMemBudget(u64, u64),
}

impl SceneSession {
    /// Run a whole script: `;`-separated statements per line; a statement STARTING with `#` or
    /// `//` is a comment (never inline — `#RRGGBBAA` color literals must survive). Errors are
    /// formatted `line {n}: {e} [{line}]` (the engine convention, byte-for-byte).
    pub fn run_script(&mut self, src: &str) -> Result<(), String> {
        for (n, raw) in src.lines().enumerate() {
            for stmt in raw.split(';') {
                let line = stmt.trim();
                if line.is_empty() || line.starts_with('#') || line.starts_with("//") {
                    continue;
                }
                let action =
                    parse_line(line).map_err(|e| format!("line {}: {} [{}]", n + 1, e, line))?;
                self.exec(action);
            }
        }
        Ok(())
    }
}

fn parse_tween(s: &str) -> Result<Tween, String> {
    Tween::parse(s).ok_or_else(|| format!("unknown tween '{}'", s))
}

fn parse_prop_token(s: &str) -> Result<TrackProp, String> {
    TrackProp::parse(s).ok_or_else(|| format!("unknown property '{}'", s))
}

pub fn parse_line(line: &str) -> Result<SceneAction, String> {
    use SceneAction::*;
    let open = line.find('(').ok_or_else(|| "expected '('".to_string())?;
    let close = line.rfind(')').ok_or_else(|| "expected ')'".to_string())?;
    if close < open {
        return Err("mismatched parens".into());
    }
    let name = line[..open].trim();
    let args_str = &line[open + 1..close];
    let args: Vec<&str> = if args_str.trim().is_empty() {
        Vec::new()
    } else {
        args_str.split(',').map(|s| s.trim()).collect()
    };

    let arg = |k: usize| -> Result<&str, String> {
        args.get(k).copied().ok_or_else(|| format!("missing arg {}", k))
    };
    let u32a = |k: usize| -> Result<u32, String> {
        arg(k)?.parse::<u32>().map_err(|_| format!("bad u32 arg {}", k))
    };
    let u16a = |k: usize| -> Result<u16, String> {
        arg(k)?.parse::<u16>().map_err(|_| format!("bad u16 arg {}", k))
    };
    let u64a = |k: usize| -> Result<u64, String> {
        arg(k)?.parse::<u64>().map_err(|_| format!("bad u64 arg {}", k))
    };
    let i32a = |k: usize| -> Result<i32, String> {
        arg(k)?.parse::<i32>().map_err(|_| format!("bad i32 arg {}", k))
    };
    let i64a = |k: usize| -> Result<i64, String> {
        arg(k)?.parse::<i64>().map_err(|_| format!("bad i64 arg {}", k))
    };
    let usza = |k: usize| -> Result<usize, String> {
        arg(k)?.parse::<usize>().map_err(|_| format!("bad usize arg {}", k))
    };
    let boola = |k: usize| -> Result<bool, String> {
        match arg(k)? {
            "true" | "1" => Ok(true),
            "false" | "0" => Ok(false),
            other => Err(format!("bad bool '{}'", other)),
        }
    };
    let color = |k: usize| -> Result<Rgba8, String> {
        Rgba8::from_hex(arg(k)?).ok_or_else(|| format!("bad color arg {}", k))
    };
    let stringa = |k: usize| -> Result<String, String> { Ok(arg(k)?.to_string()) };
    let propa = |k: usize| -> Result<TrackProp, String> { parse_prop_token(arg(k)?) };
    let tweena = |k: usize| -> Result<Tween, String> { parse_tween(arg(k)?) };

    Ok(match name {
        "NewScene" => NewScene(u16a(0)?, u16a(1)?, u32a(2)?),
        "SetFps" => SetFps(u32a(0)?),
        "SetFrameCount" => SetFrameCount(u32a(0)?),
        "SetBackground" => SetBackground(color(0)?),
        "SetLoop" => SetLoop(u32a(0)?, u32a(1)?),
        "GenProp" => GenProp(u32a(0)?, u32a(1)?, u32a(2)?, u64a(3)?),
        "GenPropSolid" => GenPropSolid(u32a(0)?, u32a(1)?, color(2)?),
        "RemoveProp" => RemoveProp(u32a(0)?),
        "RenameProp" => RenameProp(u32a(0)?, stringa(1)?),
        "SetPropStyle" => SetPropStyle(
            u32a(0)?,
            match arg(1)? {
                "nearest" => PixelStyle::Nearest,
                "cleanedge" => PixelStyle::CleanEdge,
                other => return Err(format!("unknown style '{}'", other)),
            },
        ),
        "SetCycleStep" => SetCycleStep(u32a(0)?, u32a(1)?, u16a(2)?),
        "SetCycleAll" => SetCycleAll(u32a(0)?, u16a(1)?),
        "PlaceActor" => PlaceActor(u32a(0)?),
        "PlaceActorAt" => PlaceActorAt(u32a(0)?, i32a(1)?, i32a(2)?),
        "DuplicateActor" => DuplicateActor(u32a(0)?),
        "RemoveActor" => RemoveActor(u32a(0)?),
        "RenameActor" => RenameActor(u32a(0)?, stringa(1)?),
        "SelectActor" => SelectActor(u32a(0)?),
        "SelectNone" => SelectNone,
        "SetActorMode" => SetActorMode(
            u32a(0)?,
            match arg(1)? {
                "playing" => ActorMode::Playing,
                "posing" => ActorMode::Posing,
                other => return Err(format!("unknown mode '{}'", other)),
            },
        ),
        "SetPinTo" => SetPinTo(u32a(0)?, u32a(1)?),
        "ClearPin" => ClearPin(u32a(0)?),
        "ReorderActor" => ReorderActor(usza(0)?, usza(1)?),
        "SetActorVisible" => SetActorVisible(u32a(0)?, boola(1)?),
        "SetBase" => SetBase(u32a(0)?, propa(1)?, i64a(2)?),
        "SetKey" => SetKey(u32a(0)?, propa(1)?, u32a(2)?, i64a(3)?),
        "SetKeyTween" => SetKeyTween(u32a(0)?, propa(1)?, u32a(2)?, i64a(3)?, tweena(4)?),
        "RemoveKey" => RemoveKey(u32a(0)?, propa(1)?, u32a(2)?),
        "MoveKey" => MoveKey(u32a(0)?, propa(1)?, u32a(2)?, u32a(3)?),
        "MoveActorKeys" => MoveActorKeys(u32a(0)?, u32a(1)?, u32a(2)?),
        "SetTween" => SetTween(u32a(0)?, propa(1)?, u32a(2)?, tweena(3)?),
        "ClearTrack" => ClearTrack(u32a(0)?, propa(1)?),
        "SetAtPlayhead" => SetAtPlayhead(u32a(0)?, propa(1)?, i64a(2)?),
        "BeginGesture" => BeginGesture,
        "EndGesture" => EndGesture,
        "SetPlayhead" => SetPlayhead(u32a(0)?),
        "SetAutoKey" => SetAutoKey(boola(0)?),
        "Play" => Play,
        "Pause" => Pause,
        "AdvanceClock" => AdvanceClock(u64a(0)?),
        "Undo" => Undo,
        "Redo" => Redo,
        "ClearHistory" => ClearHistory,
        "SetMemBudget" => SetMemBudget(u64a(0)?, u64a(1)?),
        other => return Err(format!("unknown action '{}'", other)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_representative_lines() {
        assert_eq!(parse_line("NewScene(64,64,12500)").unwrap(), SceneAction::NewScene(64, 64, 12_500));
        assert_eq!(
            parse_line("SetAtPlayhead(3, x, -40)").unwrap(),
            SceneAction::SetAtPlayhead(3, TrackProp::X, -40)
        );
        assert_eq!(
            parse_line("SetTween(1, rot, 12, easeinout)").unwrap(),
            SceneAction::SetTween(1, TrackProp::Rot, 12, Tween::EaseInOut)
        );
        assert_eq!(parse_line("EndGesture()").unwrap(), SceneAction::EndGesture);
        assert!(parse_line("SetTween(1, rot, 12, bounce)").is_err());
        assert!(parse_line("Nonsense(1)").is_err());
        assert!(parse_line("SetKey(1, warp, 0, 0)").is_err());
    }
}
