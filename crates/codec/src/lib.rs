//! Image import/export (SPEC §16). Decodes GIF/PNG/APNG/JPEG/BMP/WebP into the engine's
//! `DecodedFrame`s (animated formats yield multiple frames with per-frame durations) and
//! encodes documents to PNG (per-frame / sprite-sheet) and animated GIF.
//!
//! Also hosts the `.mkpx` **compact** (DEFLATE) envelope ([`mkpx_compact`]) — the peripheral,
//! explicit/export save profile; the engine core reads/writes only the uncompressed `plain` form.

pub mod mkpx_compact;

use image::codecs::gif::{GifDecoder, GifEncoder};
use image::{AnimationDecoder, Delay, Frame as ImgFrame, ImageDecoder, ImageFormat, RgbaImage};
use makapix_engine::import::DecodedFrame;
use std::io::Cursor;

#[derive(Debug)]
pub enum CodecError {
    Decode(String),
    Encode(String),
    /// The per-frame progress callback asked the encode to stop (user cancel).
    Canceled,
    Unsupported,
}

impl std::fmt::Display for CodecError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CodecError::Decode(s) => write!(f, "decode error: {}", s),
            CodecError::Encode(s) => write!(f, "encode error: {}", s),
            CodecError::Canceled => write!(f, "canceled"),
            CodecError::Unsupported => write!(f, "unsupported format"),
        }
    }
}

/// Per-frame progress hook for the multi-frame encoders: called as `progress(done, total)` after
/// each frame is encoded; return `false` to abort the encode with [`CodecError::Canceled`].
pub type EncodeProgress<'a> = &'a mut dyn FnMut(usize, usize) -> bool;

const MAX_DIM: u32 = 4096;
/// Hard cap on decoded animation frames — mirrors the engine's `MAX_FRAMES`. Untrusted GIF/APNG
/// frame counts are bounded *before* materializing them so a tiny file can't expand to gigabytes.
const MAX_DECODE_FRAMES: usize = makapix_engine::document::MAX_FRAMES;
/// Aggregate cap on decoded RGBA across ALL frames of one animation. The per-frame dimension cap
/// and the frame-count cap are independent, so their product is unbounded: a compositing decoder
/// (GIF/APNG both composite each sub-frame onto the full logical screen) turns a few-KB file of N
/// tiny sub-frames on a huge canvas into N × w × h × 4 bytes of accumulation. A 24 KB GIF measured
/// 1.7→6.5 GB in 7 s on-device before this cap (see `docs/memory-audit/REPORT.md` addendum, P-3).
/// 384 MiB clears the largest legitimate import (1024 × 256² = 256 MiB) with headroom while killing
/// a bomb within a handful of frames.
const MAX_DECODE_TOTAL_BYTES: usize = 384 * 1024 * 1024;

/// Decode limits applied to every decoder so over-size input fails *during* decode, before a huge
/// allocation happens (the dimension check used to run only after the full decode). [audit F-3]
fn limits() -> image::Limits {
    let mut l = image::Limits::default();
    l.max_image_width = Some(MAX_DIM);
    l.max_image_height = Some(MAX_DIM);
    l.max_alloc = Some(512 * 1024 * 1024); // ≈ MAX_DIM² RGBA with generous headroom
    l
}

/// Decode an image file (by content) into one or more `DecodedFrame`s.
pub fn decode(bytes: &[u8]) -> Result<Vec<DecodedFrame>, CodecError> {
    let format = image::guess_format(bytes).map_err(|e| CodecError::Decode(e.to_string()))?;
    match format {
        ImageFormat::Gif => {
            let mut dec = GifDecoder::new(Cursor::new(bytes)).map_err(de)?;
            dec.set_limits(limits()).map_err(de)?;
            decode_animated(dec)
        }
        ImageFormat::WebP => {
            // Try animated; fall back to static.
            match image::codecs::webp::WebPDecoder::new(Cursor::new(bytes)) {
                Ok(mut dec) if dec.has_animation() => {
                    dec.set_limits(limits()).map_err(de)?;
                    decode_animated(dec)
                }
                _ => decode_static(bytes),
            }
        }
        ImageFormat::Png => {
            // APNG → animated; else static. Limits set before `apng()` so they carry into frames.
            let mut dec = image::codecs::png::PngDecoder::new(Cursor::new(bytes)).map_err(de)?;
            dec.set_limits(limits()).map_err(de)?;
            if dec.is_apng().map_err(de)? {
                decode_animated(dec.apng().map_err(de)?)
            } else {
                decode_static(bytes)
            }
        }
        _ => decode_static(bytes),
    }
}

fn de(e: image::ImageError) -> CodecError {
    CodecError::Decode(e.to_string())
}

fn decode_static(bytes: &[u8]) -> Result<Vec<DecodedFrame>, CodecError> {
    // Decode through an ImageReader carrying `limits()` so dimensions/allocation are bounded
    // *during* decode rather than checked after a full materialization. [audit F-3]
    let mut reader = image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|e| CodecError::Decode(e.to_string()))?;
    reader.limits(limits());
    let img = reader.decode().map_err(de)?;
    let rgba = img.to_rgba8();
    let (w, h) = (rgba.width(), rgba.height());
    if w > MAX_DIM || h > MAX_DIM {
        return Err(CodecError::Decode("image too large".into()));
    }
    Ok(vec![DecodedFrame { rgba: rgba.into_raw(), w, h, duration_us: 100_000 }])
}

fn decode_animated<'a>(decoder: impl AnimationDecoder<'a>) -> Result<Vec<DecodedFrame>, CodecError> {
    decode_animated_capped(decoder, MAX_DECODE_TOTAL_BYTES)
}

/// [`decode_animated`] with an explicit aggregate-bytes cap — the cap is a parameter so the test
/// suite can exercise the bomb path with a tiny cap and tiny frames instead of allocating the real
/// 384 MiB. Production always uses [`MAX_DECODE_TOTAL_BYTES`].
fn decode_animated_capped<'a>(
    decoder: impl AnimationDecoder<'a>,
    total_cap: usize,
) -> Result<Vec<DecodedFrame>, CodecError> {
    // Decode frames lazily, one at a time, capping the count BEFORE materializing more — never
    // `collect_frames()`, which would eagerly decode every frame of a bomb into memory. [F-3]
    let mut out = Vec::new();
    let mut total_bytes = 0usize; // running sum of decoded RGBA, capped to stop bombs [P-3]
    for (i, frame) in decoder.into_frames().enumerate() {
        if i >= MAX_DECODE_FRAMES {
            return Err(CodecError::Decode("too many frames".into()));
        }
        let fr = frame.map_err(de)?;
        let (num, den) = fr.delay().numer_denom_ms();
        let dur_ms = if den == 0 { 100 } else { num / den.max(1) };
        let buf: RgbaImage = fr.into_buffer();
        let (w, h) = (buf.width(), buf.height());
        if w > MAX_DIM || h > MAX_DIM {
            return Err(CodecError::Decode("frame too large".into()));
        }
        // Aggregate cap: bound the SUM across frames, not just each one. The per-frame check above
        // (≤4096²·4 = 64 MiB/frame) and `image`'s own per-frame `max_alloc` both reset each frame,
        // so only this running total stops an N-frame bomb. At most one frame of overshoot. [P-3]
        total_bytes = total_bytes.saturating_add((w as usize) * (h as usize) * 4);
        if total_bytes > total_cap {
            return Err(CodecError::Decode("animation too large".into()));
        }
        out.push(DecodedFrame {
            rgba: buf.into_raw(),
            w,
            h,
            duration_us: (dur_ms.max(1) * 1000),
        });
    }
    if out.is_empty() {
        return Err(CodecError::Decode("no frames".into()));
    }
    Ok(out)
}

/// Integer nearest-neighbor upscale (each pixel becomes a `scale`×`scale` block) — crisp
/// pixel-art enlargement for the export paths. `scale` ≤ 1 returns a plain copy.
pub fn upscale_nearest(w: u32, h: u32, rgba: &[u8], scale: u32) -> Vec<u8> {
    if scale <= 1 {
        return rgba.to_vec();
    }
    let (w, h, s) = (w as usize, h as usize, scale as usize);
    let ow = w * s;
    let mut out = vec![0u8; ow * h * s * 4];
    let mut row = vec![0u8; ow * 4];
    for y in 0..h {
        // Expand one source row horizontally, then stamp it `s` times vertically (memcpy).
        for x in 0..w {
            let src = &rgba[(y * w + x) * 4..(y * w + x) * 4 + 4];
            for i in 0..s {
                row[(x * s + i) * 4..(x * s + i) * 4 + 4].copy_from_slice(src);
            }
        }
        for i in 0..s {
            let o = (y * s + i) * ow * 4;
            out[o..o + ow * 4].copy_from_slice(&row);
        }
    }
    out
}

/// Bounding rect `(x, y, w, h)` in source pixels of every RGBA pixel differing between two
/// same-size buffers, or `None` when they are byte-identical. Drives the animated-WebP delta
/// frames: rows are compared as whole slices first (cheap skip for unchanged rows), then the
/// first/last differing pixel of each changed row widens the box.
fn diff_rect(w: u32, h: u32, prev: &[u8], cur: &[u8]) -> Option<(u32, u32, u32, u32)> {
    let w = w as usize;
    let row_bytes = w * 4;
    let (mut min_x, mut max_x, mut min_y, mut max_y) = (usize::MAX, 0usize, usize::MAX, 0usize);
    for y in 0..h as usize {
        let a = &prev[y * row_bytes..(y + 1) * row_bytes];
        let b = &cur[y * row_bytes..(y + 1) * row_bytes];
        if a == b {
            continue;
        }
        let first = (0..w).find(|&x| a[x * 4..x * 4 + 4] != b[x * 4..x * 4 + 4]).unwrap();
        let last = (0..w).rfind(|&x| a[x * 4..x * 4 + 4] != b[x * 4..x * 4 + 4]).unwrap();
        min_x = min_x.min(first);
        max_x = max_x.max(last);
        if min_y == usize::MAX {
            min_y = y;
        }
        max_y = y;
    }
    if min_y == usize::MAX {
        return None;
    }
    Some((min_x as u32, min_y as u32, (max_x - min_x + 1) as u32, (max_y - min_y + 1) as u32))
}

/// Copy the `rw`×`rh` RGBA sub-rect at (`x`,`y`) out of a `w`-pixel-wide buffer (row memcpys).
fn crop_rgba(w: u32, rgba: &[u8], x: u32, y: u32, rw: u32, rh: u32) -> Vec<u8> {
    let (w, x, y, rw, rh) = (w as usize, x as usize, y as usize, rw as usize, rh as usize);
    let mut out = Vec::with_capacity(rw * rh * 4);
    for row in y..y + rh {
        let start = (row * w + x) * 4;
        out.extend_from_slice(&rgba[start..start + rw * 4]);
    }
    out
}

/// Encode a single frame's RGBA to PNG.
pub fn encode_png(w: u32, h: u32, rgba: &[u8]) -> Result<Vec<u8>, CodecError> {
    let img = RgbaImage::from_raw(w, h, rgba.to_vec()).ok_or(CodecError::Unsupported)?;
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, ImageFormat::Png).map_err(|e| CodecError::Encode(e.to_string()))?;
    Ok(out.into_inner())
}

/// Encode a single frame's RGBA to a **lossless** WebP (image-webp, pure Rust). The recommended
/// format for Makapix Club submissions.
pub fn encode_webp(w: u32, h: u32, rgba: &[u8]) -> Result<Vec<u8>, CodecError> {
    if rgba.len() != (w as usize) * (h as usize) * 4 {
        return Err(CodecError::Unsupported);
    }
    let mut out = Vec::new();
    image_webp::WebPEncoder::new(&mut out)
        .encode(rgba, w, h, image_webp::ColorType::Rgba8)
        .map_err(|e| CodecError::Encode(e.to_string()))?;
    Ok(out)
}

/// Encode frames to an **animated lossless** WebP (durations in microseconds). Each frame is encoded
/// to a lossless VP8L bitstream (image-webp) and the bitstreams are muxed into a VP8X/ANIM/ANMF
/// container by hand — pure Rust, no libwebp. The first frame covers the full canvas; every later
/// frame is a delta sub-frame holding only the changed pixels' bounding rect (a 1×1 rewrite when
/// identical), always exactly one ANMF per input frame. A single-frame input is just a static WebP.
pub fn encode_animated_webp(w: u32, h: u32, frames: &[(Vec<u8>, u32)]) -> Result<Vec<u8>, CodecError> {
    encode_animated_webp_with(w, h, frames, 1, &mut |_, _| true)
}

/// [`encode_animated_webp`] with an integer nearest-neighbor upscale (`scale`, clamped to 1..=32
/// and applied one frame at a time, so a big upscale never holds more than one enlarged frame)
/// and a per-frame [`EncodeProgress`] hook (VP8L encoding dominates the runtime, so per-frame
/// granularity tracks the real work).
pub fn encode_animated_webp_with(
    w: u32,
    h: u32,
    frames: &[(Vec<u8>, u32)],
    scale: u32,
    progress: EncodeProgress,
) -> Result<Vec<u8>, CodecError> {
    // Thin adapter over the streaming core (clones each slice frame, as before).
    let mut it = frames.iter();
    encode_animated_webp_streaming(w, h, frames.len(), || it.next().map(|(r, d)| (r.clone(), *d)), scale, progress)
}

/// Streaming lossless-WebP encoder (the [`encode_gif_streaming`] twin): pulls one frame at a time
/// via `next` so the caller composites on demand and never holds all frames' RGBA at once (audit
/// #10). Only the small **compressed** VP8L chunks accumulate — never the raw frames — so the peak
/// is the current + previous raw **source** frames (kept for the delta diff) plus the upscaled
/// changed sub-rect; two full upscaled frames are never resident. Byte-identical to the slice path.
pub fn encode_animated_webp_streaming(
    w: u32,
    h: u32,
    count: usize,
    mut next: impl FnMut() -> Option<(Vec<u8>, u32)>,
    scale: u32,
    progress: EncodeProgress,
) -> Result<Vec<u8>, CodecError> {
    if count == 0 {
        return Err(CodecError::Unsupported);
    }
    let scale = scale.clamp(1, 32);
    let (sw, sh) = (w, h); // source dims — what the per-frame upscaler reads
    let up = move |rgba: &[u8]| upscale_nearest(sw, sh, rgba, scale);
    let (w, h) = (w * scale, h * scale); // output dims — the bitstreams + container below
    if count == 1 {
        let (rgba, _dur) = next().ok_or(CodecError::Unsupported)?;
        let out = encode_webp(w, h, &up(&rgba))?;
        if !progress(1, 1) {
            return Err(CodecError::Canceled);
        }
        return Ok(out);
    }
    // 1. Lossless-encode each frame's changed sub-rect and pull out its VP8L bitstream chunk.
    //    Frame 0 is the full canvas; every later frame encodes only the bounding rect of the
    //    pixels that differ from the previous frame (a 1×1 rewrite when identical) — the diff
    //    runs at SOURCE resolution so only the changed area is ever upscaled.
    struct AnmfFrame {
        vp8l: Vec<u8>,
        dur_ms: u32,
        // Output-space rect; x/y kept even because ANMF stores them halved.
        x: u32,
        y: u32,
        w: u32,
        h: u32,
    }
    let src_len = (sw as usize) * (sh as usize) * 4;
    let mut frames_out: Vec<AnmfFrame> = Vec::with_capacity(count);
    let mut prev: Option<Vec<u8>> = None;
    let mut i = 0usize;
    while let Some((rgba, dur_us)) = next() {
        if rgba.len() != src_len {
            return Err(CodecError::Unsupported);
        }
        let (mut sx, mut sy, mut rw, mut rh) = match &prev {
            None => (0, 0, sw, sh),
            Some(p) => match diff_rect(sw, sh, p, &rgba) {
                Some(r) => r,
                None => {
                    // Identical frame: a 1×1 OUTPUT-space rect rewriting pixel (0,0) with its own
                    // value — the smallest legal ANMF payload (the format cannot express an empty
                    // frame, and its rect need not align to upscaled source blocks). Kept out of
                    // the generic path because upscaling it to scale×scale would cross image-webp's
                    // single-pixel→full-Huffman-trees cliff (~40 B vs ~160 B).
                    let webp = encode_webp(1, 1, &rgba[0..4])?;
                    let chunk = extract_vp8l(&webp)
                        .ok_or_else(|| CodecError::Encode("missing VP8L chunk".into()))?;
                    frames_out.push(AnmfFrame {
                        vp8l: chunk,
                        dur_ms: (dur_us / 1000).max(1),
                        x: 0,
                        y: 0,
                        w: 1,
                        h: 1,
                    });
                    prev = Some(rgba);
                    i += 1;
                    if !progress(i, count) {
                        return Err(CodecError::Canceled);
                    }
                    continue;
                }
            },
        };
        // ANMF stores x/2 and y/2, so the output-space origin must be even. `sx*scale` is odd
        // only when both factors are odd, so `sx-1 >= 0` and the snapped origin lands even; the
        // right/bottom edge is unchanged, keeping the rect inside the canvas.
        if (sx * scale) % 2 == 1 {
            sx -= 1;
            rw += 1;
        }
        if (sy * scale) % 2 == 1 {
            sy -= 1;
            rh += 1;
        }
        let sub = if (rw, rh) == (sw, sh) {
            upscale_nearest(sw, sh, &rgba, scale)
        } else {
            upscale_nearest(rw, rh, &crop_rgba(sw, &rgba, sx, sy, rw, rh), scale)
        };
        let webp = encode_webp(rw * scale, rh * scale, &sub)?;
        let chunk = extract_vp8l(&webp).ok_or_else(|| CodecError::Encode("missing VP8L chunk".into()))?;
        frames_out.push(AnmfFrame {
            vp8l: chunk,
            dur_ms: (dur_us / 1000).max(1),
            x: sx * scale,
            y: sy * scale,
            w: rw * scale,
            h: rh * scale,
        });
        prev = Some(rgba);
        i += 1;
        if !progress(i, count) {
            return Err(CodecError::Canceled);
        }
    }
    // 2. Assemble the container body: VP8X, ANIM, then one ANMF per frame.
    let mut body = Vec::new();
    // VP8X: feature flags (Animation + Alpha) + reserved + canvas (w-1, h-1) as 24-bit LE.
    let mut vp8x = Vec::with_capacity(10);
    vp8x.push(0x12); // bit 1 = Animation, bit 4 = Alpha
    vp8x.extend_from_slice(&[0, 0, 0]);
    vp8x.extend_from_slice(&(w - 1).to_le_bytes()[0..3]);
    vp8x.extend_from_slice(&(h - 1).to_le_bytes()[0..3]);
    push_chunk(&mut body, b"VP8X", &vp8x);
    // ANIM: transparent background (BGRA) + infinite loop.
    let mut anim = Vec::with_capacity(6);
    anim.extend_from_slice(&[0, 0, 0, 0]);
    anim.extend_from_slice(&0u16.to_le_bytes()); // 0 = loop forever
    push_chunk(&mut body, b"ANIM", &anim);
    // ANMF per frame: frame 0 covers the full canvas; later frames only their changed bounding
    // rect (1×1 when identical), overwrite (no blend), no dispose — the untouched canvas carries
    // over. X/Y are stored halved; the encode loop keeps them even.
    for f in &frames_out {
        debug_assert!(f.x % 2 == 0 && f.y % 2 == 0);
        let mut anmf = Vec::new();
        anmf.extend_from_slice(&(f.x / 2).to_le_bytes()[0..3]);
        anmf.extend_from_slice(&(f.y / 2).to_le_bytes()[0..3]);
        anmf.extend_from_slice(&(f.w - 1).to_le_bytes()[0..3]);
        anmf.extend_from_slice(&(f.h - 1).to_le_bytes()[0..3]);
        anmf.extend_from_slice(&f.dur_ms.to_le_bytes()[0..3]);
        anmf.push(0x02); // B = 1 (do not blend / overwrite), D = 0 (no dispose)
        push_chunk(&mut anmf, b"VP8L", &f.vp8l);
        push_chunk(&mut body, b"ANMF", &anmf);
    }
    // 3. RIFF wrapper.
    let mut out = Vec::with_capacity(body.len() + 12);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&((body.len() + 4) as u32).to_le_bytes()); // "WEBP" + body
    out.extend_from_slice(b"WEBP");
    out.extend_from_slice(&body);
    Ok(out)
}

/// Pull the raw VP8L (lossless) chunk payload out of a simple WebP file.
fn extract_vp8l(webp: &[u8]) -> Option<Vec<u8>> {
    if webp.len() < 12 || &webp[0..4] != b"RIFF" || &webp[8..12] != b"WEBP" {
        return None;
    }
    let mut pos = 12;
    while pos + 8 <= webp.len() {
        let size = u32::from_le_bytes([webp[pos + 4], webp[pos + 5], webp[pos + 6], webp[pos + 7]]) as usize;
        let start = pos + 8;
        let end = start.checked_add(size)?;
        if end > webp.len() {
            return None;
        }
        if &webp[pos..pos + 4] == b"VP8L" {
            return Some(webp[start..end].to_vec());
        }
        pos = end + (size & 1); // chunks are padded to an even size
    }
    None
}

/// Append a RIFF chunk (fourcc + LE size + data, padded to an even length).
fn push_chunk(buf: &mut Vec<u8>, fourcc: &[u8; 4], data: &[u8]) {
    buf.extend_from_slice(fourcc);
    buf.extend_from_slice(&(data.len() as u32).to_le_bytes());
    buf.extend_from_slice(data);
    if data.len() & 1 == 1 {
        buf.push(0);
    }
}

/// Encode frames to an animated GIF (durations in microseconds).
pub fn encode_gif(w: u32, h: u32, frames: &[(Vec<u8>, u32)]) -> Result<Vec<u8>, CodecError> {
    encode_gif_with(w, h, frames, 1, &mut |_, _| true)
}

/// [`encode_gif`] with an integer nearest-neighbor upscale (`scale`, clamped to 1..=32 and
/// applied one frame at a time, so a big upscale never holds more than one enlarged frame) and a
/// per-frame [`EncodeProgress`] hook (each frame's color quantization dominates the runtime, so
/// per-frame granularity tracks the real work).
pub fn encode_gif_with(
    w: u32,
    h: u32,
    frames: &[(Vec<u8>, u32)],
    scale: u32,
    progress: EncodeProgress,
) -> Result<Vec<u8>, CodecError> {
    // Thin adapter over the streaming core: pull frames from the slice (cloning each, as the old
    // slice path always did at scale 1). Keeps every existing caller/test working unchanged.
    let mut it = frames.iter();
    encode_gif_streaming(w, h, frames.len(), || it.next().map(|(r, d)| (r.clone(), *d)), scale, progress)
}

/// Streaming GIF encoder: pulls one `(rgba, duration_us)` frame at a time via `next` (so the caller
/// can composite on demand and never hold all frames at once — the export peak fix, audit #10),
/// `count` = total frames (for progress). Byte-identical to the slice path: same frames, order,
/// scale, encoder calls. Each frame is quantized and LZW-written straight into `out`; nothing
/// accumulates but the output.
pub fn encode_gif_streaming(
    w: u32,
    h: u32,
    count: usize,
    mut next: impl FnMut() -> Option<(Vec<u8>, u32)>,
    scale: u32,
    progress: EncodeProgress,
) -> Result<Vec<u8>, CodecError> {
    let scale = scale.clamp(1, 32);
    let mut out = Vec::new();
    {
        let mut enc = GifEncoder::new(&mut out);
        enc.set_repeat(image::codecs::gif::Repeat::Infinite)
            .map_err(|e| CodecError::Encode(e.to_string()))?;
        let mut i = 0usize;
        while let Some((rgba, dur_us)) = next() {
            let data = if scale == 1 { rgba } else { upscale_nearest(w, h, &rgba, scale) };
            let img = RgbaImage::from_raw(w * scale, h * scale, data).ok_or(CodecError::Unsupported)?;
            let delay = Delay::from_numer_denom_ms((dur_us / 1000).max(1), 1);
            enc.encode_frame(ImgFrame::from_parts(img, 0, 0, delay))
                .map_err(|e| CodecError::Encode(e.to_string()))?;
            i += 1;
            if !progress(i, count) {
                return Err(CodecError::Canceled);
            }
        }
    }
    Ok(out)
}

/// Encode frames to a horizontal PNG sprite sheet (`cols` per row).
pub fn encode_sprite_sheet(w: u32, h: u32, frames: &[Vec<u8>], cols: u32) -> Result<Vec<u8>, CodecError> {
    if frames.is_empty() {
        return Err(CodecError::Unsupported);
    }
    let cols = cols.max(1);
    let rows = (frames.len() as u32).div_ceil(cols);
    let mut sheet = RgbaImage::new(w * cols, h * rows);
    for (i, f) in frames.iter().enumerate() {
        let cx = (i as u32 % cols) * w;
        let cy = (i as u32 / cols) * h;
        if let Some(src) = RgbaImage::from_raw(w, h, f.clone()) {
            for y in 0..h {
                for x in 0..w {
                    sheet.put_pixel(cx + x, cy + y, *src.get_pixel(x, y));
                }
            }
        }
    }
    let mut out = Cursor::new(Vec::new());
    sheet.write_to(&mut out, ImageFormat::Png).map_err(|e| CodecError::Encode(e.to_string()))?;
    Ok(out.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn png_roundtrip_through_codec() {
        let (w, h) = (8u32, 8u32);
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for i in (0..rgba.len()).step_by(4) {
            rgba[i] = 200;
            rgba[i + 3] = 255;
        }
        let png = encode_png(w, h, &rgba).unwrap();
        let frames = decode(&png).unwrap();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].w, 8);
        assert_eq!(frames[0].rgba[0], 200);
    }

    #[test]
    fn gif_animation_roundtrip() {
        let (w, h) = (4u32, 4u32);
        let red = vec![255u8, 0, 0, 255].repeat((w * h) as usize);
        let blue = vec![0u8, 0, 255, 255].repeat((w * h) as usize);
        let gif = encode_gif(w, h, &[(red, 80_000), (blue, 120_000)]).unwrap();
        let frames = decode(&gif).unwrap();
        assert_eq!(frames.len(), 2);
        assert!(frames[0].duration_us >= 1000);
    }

    #[test]
    fn webp_static_lossless_roundtrip() {
        let (w, h) = (4u32, 4u32);
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        rgba[0..4].copy_from_slice(&[255, 0, 0, 255]); // (0,0) red, opaque
        rgba[20..24].copy_from_slice(&[0, 200, 0, 128]); // (1,1) green, half-alpha
        let webp = encode_webp(w, h, &rgba).unwrap();
        assert_eq!(&webp[0..4], b"RIFF");
        assert_eq!(&webp[8..12], b"WEBP");
        let frames = decode(&webp).unwrap();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].rgba, rgba, "lossless round-trip preserves every pixel incl. alpha");
    }

    #[test]
    fn encode_progress_reports_and_cancels() {
        let (w, h) = (4u32, 4u32);
        let red = vec![255u8, 0, 0, 255].repeat((w * h) as usize);
        let frames = vec![(red.clone(), 50_000), (red.clone(), 50_000), (red, 50_000)];
        // Progress fires once per frame with the right totals.
        let mut seen = Vec::new();
        let gif = encode_gif_with(w, h, &frames, 1, &mut |done, total| {
            seen.push((done, total));
            true
        });
        assert!(gif.is_ok());
        assert_eq!(seen, vec![(1, 3), (2, 3), (3, 3)]);
        // Returning false aborts with Canceled (both encoders).
        assert!(matches!(
            encode_gif_with(w, h, &frames, 1, &mut |done, _| done < 2),
            Err(CodecError::Canceled)
        ));
        assert!(matches!(
            encode_animated_webp_with(w, h, &frames, 1, &mut |done, _| done < 2),
            Err(CodecError::Canceled)
        ));
    }

    #[test]
    fn animated_decode_aggregate_cap() {
        // Three 64×64 frames → each decodes to 64·64·4 = 16 KiB. A 24 KiB aggregate cap admits the
        // first frame and trips on the second; the real (large) cap decodes all three. This guards
        // the bomb path (audit P-3) without allocating the production 384 MiB. The full 4096²-screen
        // bomb is exercised on-device via tools/memlab/make_gif.py (REPORT.md addendum).
        let (w, h) = (64u32, 64u32);
        let frame = vec![10u8, 20, 30, 255].repeat((w * h) as usize);
        let gif =
            encode_gif(w, h, &[(frame.clone(), 50_000), (frame.clone(), 50_000), (frame, 50_000)]).unwrap();

        let dec = GifDecoder::new(Cursor::new(&gif)).unwrap();
        let tripped = decode_animated_capped(dec, 24 * 1024);
        assert!(
            matches!(tripped, Err(CodecError::Decode(ref m)) if m == "animation too large"),
            "aggregate cap must trip on the second frame (got {})",
            match &tripped {
                Ok(f) => format!("Ok with {} frames", f.len()),
                Err(e) => format!("Err({})", e),
            }
        );

        let dec2 = GifDecoder::new(Cursor::new(&gif)).unwrap();
        assert_eq!(
            decode_animated_capped(dec2, MAX_DECODE_TOTAL_BYTES).unwrap().len(),
            3,
            "the same animation decodes fully under the production cap"
        );
    }

    #[test]
    fn upscale_nearest_expands_pixel_blocks() {
        // 2×1 red|blue at 3× → 6×3 of 3×3 blocks.
        let rgba = [255u8, 0, 0, 255, 0, 0, 255, 255];
        let up = upscale_nearest(2, 1, &rgba, 3);
        assert_eq!(up.len(), 6 * 3 * 4);
        for y in 0..3usize {
            for x in 0..6usize {
                let o = (y * 6 + x) * 4;
                let expect: [u8; 4] = if x < 3 { [255, 0, 0, 255] } else { [0, 0, 255, 255] };
                assert_eq!(&up[o..o + 4], &expect, "({x},{y})");
            }
        }
        assert_eq!(upscale_nearest(2, 1, &rgba, 1), rgba.to_vec(), "scale 1 is a plain copy");
    }

    #[test]
    fn animated_webp_upscales_losslessly() {
        let (w, h) = (2u32, 2u32);
        let red = vec![255u8, 0, 0, 255].repeat((w * h) as usize);
        let blue = vec![0u8, 0, 255, 128].repeat((w * h) as usize);
        let frames = vec![(red.clone(), 80_000), (blue, 120_000)];
        let webp = encode_animated_webp_with(w, h, &frames, 4, &mut |_, _| true).unwrap();
        let back = decode(&webp).unwrap();
        assert_eq!(back.len(), 2);
        assert_eq!((back[0].w, back[0].h), (8, 8), "4× output dimensions");
        assert_eq!(back[0].rgba, upscale_nearest(w, h, &red, 4), "upscaled frame is lossless");
    }

    #[test]
    fn webp_animation_lossless_roundtrip() {
        let (w, h) = (4u32, 4u32);
        let red = vec![255u8, 0, 0, 255].repeat((w * h) as usize);
        let blue = vec![0u8, 0, 255, 128].repeat((w * h) as usize); // semi-transparent blue
        let webp = encode_animated_webp(w, h, &[(red.clone(), 80_000), (blue.clone(), 120_000)]).unwrap();
        assert_eq!(&webp[0..4], b"RIFF");
        assert_eq!(&webp[8..12], b"WEBP");
        // The hand-built container must decode back to the exact frames (validates the mux).
        let frames = decode(&webp).unwrap();
        assert_eq!(frames.len(), 2, "two animated frames");
        assert_eq!(frames[0].rgba, red, "frame 0 lossless");
        assert_eq!(frames[1].rgba, blue, "frame 1 lossless incl. alpha");
    }

    /// Test-only ANMF walker: one `(x, y, w, h, anmf_chunk_len)` per animation frame, with the
    /// rect decoded back to output-space pixels (x/y are stored halved, w/h minus one).
    fn anmf_rects(webp: &[u8]) -> Vec<(u32, u32, u32, u32, usize)> {
        let le3 = |b: &[u8]| u32::from_le_bytes([b[0], b[1], b[2], 0]);
        let mut out = Vec::new();
        let mut pos = 12;
        while pos + 8 <= webp.len() {
            let size =
                u32::from_le_bytes([webp[pos + 4], webp[pos + 5], webp[pos + 6], webp[pos + 7]]) as usize;
            if &webp[pos..pos + 4] == b"ANMF" {
                let p = &webp[pos + 8..pos + 8 + size];
                out.push((le3(&p[0..3]) * 2, le3(&p[3..6]) * 2, le3(&p[6..9]) + 1, le3(&p[9..12]) + 1, size));
            }
            pos += 8 + size + (size & 1);
        }
        out
    }

    #[test]
    fn webp_animation_identical_frames_are_degenerate_1x1() {
        let (w, h) = (8u32, 8u32);
        let mut frame = vec![40u8, 80, 120, 255].repeat((w * h) as usize);
        frame[100..104].copy_from_slice(&[10, 20, 30, 128]); // one semi-alpha pixel must survive
        let frames = vec![(frame.clone(), 50_000); 3];
        for scale in [1u32, 2] {
            let webp = encode_animated_webp_with(w, h, &frames, scale, &mut |_, _| true).unwrap();
            let back = decode(&webp).unwrap();
            assert_eq!(back.len(), 3, "one decoded frame per source frame (scale {scale})");
            let expect = upscale_nearest(w, h, &frame, scale);
            for (i, fr) in back.iter().enumerate() {
                assert_eq!(fr.rgba, expect, "frame {i} lossless (scale {scale})");
            }
            let rects = anmf_rects(&webp);
            assert_eq!(rects.len(), 3);
            assert_eq!((rects[0].0, rects[0].1, rects[0].2, rects[0].3), (0, 0, w * scale, h * scale));
            for r in &rects[1..] {
                assert_eq!(
                    (r.0, r.1, r.2, r.3),
                    (0, 0, 1, 1),
                    "identical frame collapses to a 1×1 output rect (scale {scale})"
                );
                assert!(r.4 >= 32, "ANMF chunk must meet the decoder's 32-byte minimum (got {})", r.4);
                assert!(r.4 <= 64, "degenerate frame must stay tiny (got {})", r.4);
            }
        }
    }

    #[test]
    fn webp_animation_subrect_partial_change_roundtrip() {
        // 16×16 deterministic gradient; frame 1 changes a 3×3 region at (5,7) — including one
        // pixel dropping to half alpha and one to full transparency (the no-blend overwrite must
        // carry alpha DECREASES) — and frame 2 a 2×2 region touching the right/bottom edge.
        let (w, h) = (16u32, 16u32);
        let mut f0 = Vec::with_capacity((w * h * 4) as usize);
        for y in 0..h {
            for x in 0..w {
                f0.extend_from_slice(&[(x * 16) as u8, (y * 16) as u8, (x + y) as u8, 255]);
            }
        }
        let set = |f: &mut [u8], x: u32, y: u32, p: [u8; 4]| {
            let o = ((y * w + x) * 4) as usize;
            f[o..o + 4].copy_from_slice(&p);
        };
        let mut f1 = f0.clone();
        for (i, &(x, y)) in
            [(5, 7), (6, 7), (7, 7), (5, 8), (6, 8), (7, 8), (5, 9), (6, 9), (7, 9)].iter().enumerate()
        {
            let a = match i {
                0 => 128, // opaque → half alpha
                1 => 0,   // opaque → fully transparent
                _ => 255,
            };
            set(&mut f1, x, y, [200, 40, 40, a]);
        }
        let mut f2 = f1.clone();
        for &(x, y) in &[(14, 14), (15, 14), (14, 15), (15, 15)] {
            set(&mut f2, x, y, [0, 255, 0, 200]);
        }
        let sources = [&f0, &f1, &f2];
        let frames: Vec<(Vec<u8>, u32)> = sources.iter().map(|f| ((*f).clone(), 50_000)).collect();
        for s in [1u32, 2, 3] {
            let webp = encode_animated_webp_with(w, h, &frames, s, &mut |_, _| true).unwrap();
            assert_eq!(
                webp,
                encode_animated_webp_with(w, h, &frames, s, &mut |_, _| true).unwrap(),
                "deterministic output (scale {s})"
            );
            let back = decode(&webp).unwrap();
            assert_eq!(back.len(), 3);
            for (i, src) in sources.iter().enumerate() {
                assert_eq!(back[i].rgba, upscale_nearest(w, h, src, s), "frame {i} lossless (scale {s})");
            }
            let rects: Vec<_> = anmf_rects(&webp).iter().map(|r| (r.0, r.1, r.2, r.3)).collect();
            // Frame 1's source rect (5,7,3,3) even-snaps to (4,6,4,4) whenever sx·scale is odd.
            let f1_rect = match s {
                1 => (4, 6, 4, 4),
                2 => (10, 14, 6, 6),
                3 => (12, 18, 12, 12),
                _ => unreachable!(),
            };
            assert_eq!(rects[0], (0, 0, 16 * s, 16 * s), "frame 0 full canvas (scale {s})");
            assert_eq!(rects[1], f1_rect, "frame 1 changed rect (scale {s})");
            assert_eq!(rects[2], (14 * s, 14 * s, 2 * s, 2 * s), "frame 2 edge rect (scale {s})");
        }
    }

    #[test]
    fn webp_animation_full_change_still_full_rect() {
        let (w, h) = (4u32, 4u32);
        let red = vec![255u8, 0, 0, 255].repeat((w * h) as usize);
        let blue = vec![0u8, 0, 255, 128].repeat((w * h) as usize);
        let webp = encode_animated_webp(w, h, &[(red.clone(), 80_000), (blue.clone(), 120_000)]).unwrap();
        let rects: Vec<_> = anmf_rects(&webp).iter().map(|r| (r.0, r.1, r.2, r.3)).collect();
        assert_eq!(rects, vec![(0, 0, 4, 4), (0, 0, 4, 4)], "fully-changed frame keeps the full rect");
        let frames = decode(&webp).unwrap();
        assert_eq!(frames[0].rgba, red);
        assert_eq!(frames[1].rgba, blue);
    }
}
