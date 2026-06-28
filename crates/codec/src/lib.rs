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
}
