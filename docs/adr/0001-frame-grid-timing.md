# Animator time is a frame grid, not a continuous clock

A Makapix Animator Scene has a fixed frame rate chosen from a curated GIF-safe list (e.g.
10 / 12.5 / 20 / 25 / 50 fps), and every Key sits on a frame boundary. We rejected the
desktop-standard continuous clock (Keys at arbitrary times, sampled at render) because a Key
between frames is never rendered — nudging it changes nothing visible, which breaks the
"what you scrub is what exports" contract — and because frame snapping doubles as the
precision aid touch input needs. GIF's hundredth-of-a-second delay grid makes arbitrary
frame rates unrepresentable anyway; the curated list keeps preview timing and export timing
identical by construction. Animated Props are quantized to the Scene grid at import (whole
scene-frames per prop frame) for the same reason: non-integer clock ratios produce judder,
and pixel-art loops live and die by rhythm.

Decided 2026-07-30 during the Animator design grilling; supersedes the continuous-clock
hybrid sketched in the original brainstorm.
