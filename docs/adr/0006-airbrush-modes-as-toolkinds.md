# Airbrush modes are ToolKinds, not a ToolSettings field

The Airbrush's three modes — Dots (the original hard-pixel spray, DSL name `Airbrush` for
journal back-compat), Soft (deterministic smoothstep-falloff stamp), and Mist (center-weighted
low-alpha particle spray) — are three engine `ToolKind`s grouped under one tool tile by the
shell, like Shape's Ellipse/Triangle/Rectangle. The obvious alternative, a
`ToolSettings.airbrush_mode` field set via a `SetAirbrushMode(...)` DSL action (the Bucket
`SetFillAllLayers` pattern), was rejected for Journal leanness: `_pushToolSettings()`
re-pushes every settings line on every tool select and is deliberately shared with the replay
baseline so the two can never drift, so a settings-based mode would add one journaled line to
every tool switch of every tool, forever — whereas a ToolKind rides the `SelectTool(...)`
line that is already emitted, adding zero journal traffic. DSL names are fossilized by
replay: `Airbrush` must keep meaning the hard-pixel spray, and the new kinds are
`AirbrushSoft` and `AirbrushMist`.

Decided 2026-08-14 during the airbrush-modes grilling. Vocabulary (Dots/Soft/Mist, the
"Spray" button collision) is in `CONTEXT.md`.
