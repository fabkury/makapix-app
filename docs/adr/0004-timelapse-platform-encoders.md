# Timelapse video is silent H.264 MP4 from thin platform-encoder channels

The exported Timelapse is a silent H.264 MP4 (yuv420p, even dimensions, ≤30 fps progress with
per-frame PTS for the finale) produced by hand-written thin platform channels over the OS
hardware encoders — MediaCodec on Android, VideoToolbox on iOS — because that is the only
format the social platforms the growth loop targets (Instagram, TikTok, X, YouTube Shorts)
accept and auto-play. Windows keeps the existing pure-Rust animated-WebP/GIF exporters for
timelapse output unless a Media Foundation channel is ever written. We rejected
`ffmpeg_kit_flutter_new` (multi-MB bundled FFmpeg, LGPL obligations, and the patent posture
that retired its predecessor in January 2025), pure-Rust encoding (no production-credible
H.264 encoder exists in 2026 — `less-avc` is lossless-I_PCM-only, `rusty_h264` is weeks old
and unvalidated — and rav1e's AV1 is heavy build-time assembly for a codec Instagram/TikTok/X
reject), and shipping WebP/GIF everywhere (WebP animates only on Discord; 1024px GIF exceeds
X's 15 MB conversion cap). Rust's role stays exactly what already ships: composite plus
integer nearest-neighbor upscale handed across the bytes-only FFI seam, leaving the
engine-dependency doctrine untouched.

Decided 2026-08-11 during the replay design grilling; encoder landscape and platform survey in
`docs/replay/ANALYSIS.md` §4.2.
