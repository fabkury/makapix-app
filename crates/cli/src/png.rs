//! Minimal dependency-free PNG encoder (8-bit RGBA, stored/uncompressed DEFLATE) so the
//! harness can emit images for visual (Tier-2) inspection.

fn crc32(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    crc ^ 0xFFFF_FFFF
}

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b): (u32, u32) = (1, 0);
    for &byte in data {
        a = (a + byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let mut crc_input = Vec::with_capacity(4 + data.len());
    crc_input.extend_from_slice(kind);
    crc_input.extend_from_slice(data);
    out.extend_from_slice(&crc_input);
    out.extend_from_slice(&crc32(&crc_input).to_be_bytes());
}

/// Wrap raw bytes in a zlib stream using DEFLATE *stored* (uncompressed) blocks.
fn zlib_store(raw: &[u8]) -> Vec<u8> {
    let mut out = vec![0x78, 0x01]; // zlib header (no compression)
    let mut pos = 0;
    while pos < raw.len() {
        let block = (raw.len() - pos).min(0xFFFF);
        let last = if pos + block >= raw.len() { 1u8 } else { 0u8 };
        out.push(last); // BFINAL, BTYPE=00
        out.extend_from_slice(&(block as u16).to_le_bytes());
        out.extend_from_slice(&(!(block as u16)).to_le_bytes());
        out.extend_from_slice(&raw[pos..pos + block]);
        pos += block;
    }
    out.extend_from_slice(&adler32(raw).to_be_bytes());
    out
}

/// Encode `w×h` straight RGBA bytes (row-major) to PNG, optionally scaling up by `scale`.
pub fn encode_rgba(w: u32, h: u32, rgba: &[u8], scale: u32) -> Vec<u8> {
    let scale = scale.max(1);
    let (sw, sh) = (w * scale, h * scale);
    // raw image data with per-row filter byte 0
    let mut raw = Vec::with_capacity((sw * sh * 4 + sh) as usize);
    for y in 0..sh {
        raw.push(0);
        let sy = y / scale;
        for x in 0..sw {
            let sx = x / scale;
            let i = ((sy * w + sx) * 4) as usize;
            raw.extend_from_slice(&rgba[i..i + 4]);
        }
    }
    let mut out = Vec::new();
    out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&sw.to_be_bytes());
    ihdr.extend_from_slice(&sh.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]); // bit depth 8, color type 6 (RGBA)
    chunk(&mut out, b"IHDR", &ihdr);
    chunk(&mut out, b"IDAT", &zlib_store(&raw));
    chunk(&mut out, b"IEND", &[]);
    out
}
