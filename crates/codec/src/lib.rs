//! Image import/export (SPEC §16). Decodes GIF/PNG/APNG/JPEG/BMP/WebP into the engine's
//! `DecodedFrame`s (animated formats yield multiple frames with per-frame durations) and
//! encodes documents to PNG (per-frame / sprite-sheet) and animated GIF.

use image::codecs::gif::{GifDecoder, GifEncoder};
use image::{AnimationDecoder, Delay, Frame as ImgFrame, ImageDecoder, ImageFormat, RgbaImage};
use makapix_engine::import::DecodedFrame;
use std::io::Cursor;

#[derive(Debug)]
pub enum CodecError {
    Decode(String),
    Encode(String),
    Unsupported,
}

impl std::fmt::Display for CodecError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CodecError::Decode(s) => write!(f, "decode error: {}", s),
            CodecError::Encode(s) => write!(f, "encode error: {}", s),
            CodecError::Unsupported => write!(f, "unsupported format"),
        }
    }
}

const MAX_DIM: u32 = 4096;
/// Hard cap on decoded animation frames — mirrors the engine's `MAX_FRAMES`. Untrusted GIF/APNG
/// frame counts are bounded *before* materializing them so a tiny file can't expand to gigabytes.
const MAX_DECODE_FRAMES: usize = makapix_engine::document::MAX_FRAMES;

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
    // Decode frames lazily, one at a time, capping the count BEFORE materializing more — never
    // `collect_frames()`, which would eagerly decode every frame of a bomb into memory. [F-3]
    let mut out = Vec::new();
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
/// container by hand — pure Rust, no libwebp. A single-frame input is just a static WebP.
pub fn encode_animated_webp(w: u32, h: u32, frames: &[(Vec<u8>, u32)]) -> Result<Vec<u8>, CodecError> {
    if frames.is_empty() {
        return Err(CodecError::Unsupported);
    }
    if frames.len() == 1 {
        return encode_webp(w, h, &frames[0].0);
    }
    // 1. Lossless-encode each frame and pull out its VP8L bitstream chunk.
    let mut vp8l: Vec<(Vec<u8>, u32)> = Vec::with_capacity(frames.len());
    for (rgba, dur_us) in frames {
        let webp = encode_webp(w, h, rgba)?;
        let chunk = extract_vp8l(&webp).ok_or_else(|| CodecError::Encode("missing VP8L chunk".into()))?;
        vp8l.push((chunk, (*dur_us / 1000).max(1)));
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
    // ANMF per frame: full-canvas, overwrite (no blend), no dispose.
    for (chunk, dur_ms) in &vp8l {
        let mut anmf = Vec::new();
        anmf.extend_from_slice(&[0, 0, 0, 0, 0, 0]); // frame x, y = 0
        anmf.extend_from_slice(&(w - 1).to_le_bytes()[0..3]);
        anmf.extend_from_slice(&(h - 1).to_le_bytes()[0..3]);
        anmf.extend_from_slice(&dur_ms.to_le_bytes()[0..3]);
        anmf.push(0x02); // B = 1 (do not blend / overwrite), D = 0 (no dispose)
        push_chunk(&mut anmf, b"VP8L", chunk);
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
    let mut out = Vec::new();
    {
        let mut enc = GifEncoder::new(&mut out);
        enc.set_repeat(image::codecs::gif::Repeat::Infinite)
            .map_err(|e| CodecError::Encode(e.to_string()))?;
        for (rgba, dur_us) in frames {
            let img = RgbaImage::from_raw(w, h, rgba.clone()).ok_or(CodecError::Unsupported)?;
            let delay = Delay::from_numer_denom_ms((*dur_us / 1000).max(1), 1);
            enc.encode_frame(ImgFrame::from_parts(img, 0, 0, delay))
                .map_err(|e| CodecError::Encode(e.to_string()))?;
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
}
