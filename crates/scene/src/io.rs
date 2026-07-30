//! The `.mkps` container, format v1 (ADR-0002: fully self-contained — every Prop's art lives
//! in the file's own tile dictionary; there is nothing to reference). Built entirely on the
//! shared `engine::io::container` machinery, so it inherits the `.mkpx` v10 determinism
//! measures verbatim: typed chunks with critical/ancillary semantics, canonical LEB128,
//! first-appearance content-addressed tile dictionary, RAW/RLE/INDEXED tile codecs, whole-file
//! CRC-32C (`INTG`), and a verified semantic `content_hash`.
//!
//! Chunk order: `SHED` (crit) · `TILE` (crit) · `CAST` (crit) · `ACTS` (crit) ·
//! [ancillary…] · `INTG` (crit). The MKPZ DEFLATE envelope applies unchanged at the periphery
//! (a compact `.mkps` is sniffed compact FIRST, then by its inner signature).

use crate::model::{
    Actor, ActorMode, PixelStyle, Prop, Scene, SceneFps, Track, TrackProp, Tween, MAX_ACTORS,
    MAX_CYCLE_STEP, MAX_PROPS, MAX_PROP_DIM, MAX_PROP_FRAMES, MAX_SCENE_FRAMES,
};
use makapix_engine::buffer::RgbaBuffer;
use makapix_engine::color::Rgba8;
use makapix_engine::geom::{MAX_DIM, MIN_DIM};
use makapix_engine::io::container::{
    self, finish_intg, read_ref_grid, read_tile_dict, verify_intg, write_chunk, Reader, TileDict,
    Writer,
};
use makapix_engine::util::IdGen;

/// The `.mkps` signature (8 bytes, PNG-style hardened): high bit, `MKPS`, CR, LF, EOF.
pub const SIGNATURE_MKPS: [u8; 8] = [0x89, b'M', b'K', b'P', b'S', 0x0D, 0x0A, 0x1A];
pub const FORMAT_VERSION: u16 = 1;

const MAX_DICT_TILES: usize = 1 << 24;

#[derive(Debug)]
pub enum SceneIoError {
    BadMagic,
    UnsupportedVersion(u16),
    Container(container::IoError),
    Corrupt(&'static str),
    TooLarge(&'static str),
    UnsupportedChunk([u8; 4]),
}

impl std::fmt::Display for SceneIoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SceneIoError::BadMagic => write!(f, "not a .mkps file (bad magic)"),
            SceneIoError::UnsupportedVersion(v) => write!(f, "unsupported .mkps version {}", v),
            SceneIoError::Container(e) => write!(f, "corrupt .mkps: {}", e),
            SceneIoError::Corrupt(s) => write!(f, "corrupt .mkps: {}", s),
            SceneIoError::TooLarge(s) => write!(f, "corrupt .mkps: {} too large", s),
            SceneIoError::UnsupportedChunk(c) => {
                write!(f, "unsupported critical chunk {:?}", String::from_utf8_lossy(c))
            }
        }
    }
}

impl From<container::IoError> for SceneIoError {
    fn from(e: container::IoError) -> Self {
        match e {
            container::IoError::BadMagic => SceneIoError::BadMagic,
            other => SceneIoError::Container(other),
        }
    }
}

// i32 values ride as u32 LE bit-casts (canonical two's complement).
fn w_i32(w: &mut Writer, v: i32) {
    w.u32(v as u32);
}
fn r_i32(r: &mut Reader) -> Result<i32, container::IoError> {
    Ok(r.u32()? as i32)
}

pub fn save_to_bytes(scene: &Scene, playhead: u32) -> Vec<u8> {
    // Tile dictionary + per-prop-frame ref grids, first-appearance order (cast → frames).
    let mut dict = TileDict::new();
    let mut grids: Vec<Vec<u32>> = Vec::new();
    for p in &scene.cast {
        for f in &p.frames {
            grids.push(dict.grid_for(f));
        }
    }

    // SHED
    let mut shed = Writer::new();
    shed.u16(FORMAT_VERSION);
    shed.u16(scene.w);
    shed.u16(scene.h);
    shed.u8(scene.fps.code());
    shed.u32(scene.frame_count);
    shed.bytes(&[
        scene.background.r,
        scene.background.g,
        scene.background.b,
        scene.background.a,
    ]);
    shed.u32(playhead);
    shed.u32(scene.loop_a);
    shed.u32(scene.loop_b);
    shed.u8(0); // flags, reserved
    shed.u128(scene.content_hash());

    // TILE
    let mut tile = Writer::new();
    dict.write(&mut tile);

    // CAST
    let mut cast = Writer::new();
    cast.varint(scene.cast.len() as u32);
    let mut grid_iter = grids.iter();
    for p in &scene.cast {
        cast.u32(p.id);
        cast.str(&p.name);
        cast.u16(p.w as u16);
        cast.u16(p.h as u16);
        cast.u8(matches!(p.style, PixelStyle::CleanEdge) as u8);
        cast.u8(p.has_semi_alpha as u8);
        cast.varint(p.frames.len() as u32);
        for (fi, _) in p.frames.iter().enumerate() {
            cast.varint(p.cycle_map.get(fi).copied().unwrap_or(1) as u32);
            let grid = grid_iter.next().expect("one grid per prop frame");
            container::write_ref_grid(&mut cast, grid);
        }
    }

    // ACTS — actors in z (vec) order; ten tracks in canonical order.
    let mut acts = Writer::new();
    acts.varint(scene.actors.len() as u32);
    for a in &scene.actors {
        acts.u32(a.id);
        acts.str(&a.name);
        acts.u32(a.prop);
        acts.u8(matches!(a.mode, ActorMode::Posing) as u8);
        match a.pin_to {
            Some(p) => {
                acts.u8(1);
                acts.u32(p);
            }
            None => acts.u8(0),
        }
        acts.u8(a.visible as u8); // flags bit0
        for tp in TrackProp::ALL {
            let t = a.tracks.get(tp);
            w_i32(&mut acts, t.base);
            acts.varint(t.keys.len() as u32);
            for k in &t.keys {
                acts.varint(k.frame);
                w_i32(&mut acts, k.v);
                acts.u8(k.tween.code());
            }
        }
    }

    // Assemble.
    let mut w = Writer::new();
    w.reserve_exact(shed.len() + tile.len() + cast.len() + acts.len() + 1024);
    w.bytes(&SIGNATURE_MKPS);
    write_chunk(&mut w, b"SHED", true, shed.as_bytes());
    write_chunk(&mut w, b"TILE", true, tile.as_bytes());
    write_chunk(&mut w, b"CAST", true, cast.as_bytes());
    write_chunk(&mut w, b"ACTS", true, acts.as_bytes());
    finish_intg(&mut w);
    w.into_bytes()
}

struct Chunks<'a> {
    shed: Option<&'a [u8]>,
    tile: Option<&'a [u8]>,
    cast: Option<&'a [u8]>,
    acts: Option<&'a [u8]>,
}

/// Load a `.mkps` (plain bytes — the compact envelope is opened by the caller). Refuses
/// over-budget tile dictionaries BEFORE materializing (`hard_budget`, the scene memory hard
/// budget). Returns the Scene and the persisted playhead.
pub fn load_from_bytes(data: &[u8], hard_budget: usize) -> Result<(Scene, u32), SceneIoError> {
    let body_end = verify_intg(data, &SIGNATURE_MKPS)?;

    let mut c = Chunks { shed: None, tile: None, cast: None, acts: None };
    container::walk_chunks(data, body_end, b"SHED", "SHED not first", |fourcc, critical, payload| {
        let slot = match fourcc {
            b"SHED" => &mut c.shed,
            b"TILE" => &mut c.tile,
            b"CAST" => &mut c.cast,
            b"ACTS" => &mut c.acts,
            _ => {
                if critical {
                    return Err(container::IoError::UnsupportedChunk(*fourcc));
                }
                return Ok(()); // unknown ancillary → skip
            }
        };
        if slot.is_some() {
            return Err(container::IoError::Corrupt("duplicate chunk"));
        }
        *slot = Some(payload);
        Ok(())
    })?;
    let shed_pl = c.shed.ok_or(SceneIoError::Corrupt("no SHED"))?;
    let tile_pl = c.tile.ok_or(SceneIoError::Corrupt("no TILE"))?;
    let cast_pl = c.cast.ok_or(SceneIoError::Corrupt("no CAST"))?;
    let acts_pl = c.acts.ok_or(SceneIoError::Corrupt("no ACTS"))?;

    // --- SHED ---
    let mut sr = Reader::new(shed_pl);
    let version = sr.u16()?;
    if version != FORMAT_VERSION {
        return Err(SceneIoError::UnsupportedVersion(version));
    }
    let w = sr.u16()?;
    let h = sr.u16()?;
    if !(MIN_DIM..=MAX_DIM).contains(&w) || !(MIN_DIM..=MAX_DIM).contains(&h) {
        return Err(SceneIoError::Corrupt("scene size out of range"));
    }
    let fps = SceneFps::from_code(sr.u8()?).ok_or(SceneIoError::Corrupt("fps"))?;
    let frame_count = sr.u32()?;
    if frame_count == 0 || frame_count > MAX_SCENE_FRAMES {
        return Err(SceneIoError::Corrupt("frame count"));
    }
    let bg = sr.take(4)?;
    let background = Rgba8::new(bg[0], bg[1], bg[2], bg[3]);
    let playhead = sr.u32()?.min(frame_count - 1);
    let loop_a = sr.u32()?;
    let loop_b = sr.u32()?;
    if loop_a > loop_b || loop_b >= frame_count {
        return Err(SceneIoError::Corrupt("loop region"));
    }
    let _flags = sr.u8()?;
    let stored_hash = sr.u128()?;

    // --- TILE (budget-refused before materializing) ---
    let mut tr = Reader::new(tile_pl);
    let dict = read_tile_dict(&mut tr, MAX_DICT_TILES, hard_budget).map_err(|e| match e {
        container::IoError::TooLarge(s) => SceneIoError::TooLarge(s),
        other => SceneIoError::Container(other),
    })?;

    // --- CAST ---
    let mut cr = Reader::new(cast_pl);
    let prop_count = cr.varint()? as usize;
    if prop_count > MAX_PROPS {
        return Err(SceneIoError::TooLarge("cast"));
    }
    let mut cast_v: Vec<Prop> = Vec::with_capacity(prop_count);
    let mut max_prop_id = 0u32;
    for _ in 0..prop_count {
        let id = cr.u32()?;
        if cast_v.iter().any(|p| p.id == id) {
            return Err(SceneIoError::Corrupt("duplicate prop id"));
        }
        max_prop_id = max_prop_id.max(id);
        let name = cr.str()?;
        let pw = cr.u16()? as u32;
        let ph = cr.u16()? as u32;
        if pw == 0 || ph == 0 || pw > MAX_PROP_DIM || ph > MAX_PROP_DIM {
            return Err(SceneIoError::Corrupt("prop size"));
        }
        let style = match cr.u8()? {
            0 => PixelStyle::Nearest,
            1 => PixelStyle::CleanEdge,
            _ => return Err(SceneIoError::Corrupt("style")),
        };
        let has_semi_alpha = match cr.u8()? {
            0 => false,
            1 => true,
            _ => return Err(SceneIoError::Corrupt("semi-alpha flag")),
        };
        let frame_count = cr.varint()? as usize;
        if frame_count == 0 || frame_count > MAX_PROP_FRAMES {
            return Err(SceneIoError::Corrupt("prop frame count"));
        }
        let mut frames = Vec::with_capacity(frame_count);
        let mut cycle_map = Vec::with_capacity(frame_count);
        for _ in 0..frame_count {
            let steps = cr.varint()?;
            if steps == 0 || steps > MAX_CYCLE_STEP as u32 {
                return Err(SceneIoError::Corrupt("cycle step"));
            }
            cycle_map.push(steps as u16);
            let mut pixels = RgbaBuffer::new(pw, ph);
            read_ref_grid(&mut cr, &dict, &mut pixels)?;
            frames.push(pixels);
        }
        cast_v.push(Prop {
            id,
            name,
            w: pw,
            h: ph,
            frames,
            cycle_map,
            style,
            has_semi_alpha,
            art_epoch: 0,
        });
    }

    // --- ACTS ---
    let mut ar = Reader::new(acts_pl);
    let actor_count = ar.varint()? as usize;
    if actor_count > MAX_ACTORS {
        return Err(SceneIoError::TooLarge("actors"));
    }
    let mut actors: Vec<Actor> = Vec::with_capacity(actor_count);
    let mut max_actor_id = 0u32;
    for _ in 0..actor_count {
        let id = ar.u32()?;
        if actors.iter().any(|a| a.id == id) {
            return Err(SceneIoError::Corrupt("duplicate actor id"));
        }
        max_actor_id = max_actor_id.max(id);
        let name = ar.str()?;
        let prop = ar.u32()?;
        if !cast_v.iter().any(|p| p.id == prop) {
            return Err(SceneIoError::Corrupt("actor prop ref"));
        }
        let mode = match ar.u8()? {
            0 => ActorMode::Playing,
            1 => ActorMode::Posing,
            _ => return Err(SceneIoError::Corrupt("mode")),
        };
        let pin_to = match ar.u8()? {
            0 => None,
            1 => Some(ar.u32()?),
            _ => return Err(SceneIoError::Corrupt("pin flag")),
        };
        if pin_to == Some(id) {
            return Err(SceneIoError::Corrupt("pin"));
        }
        let flags = ar.u8()?;
        let visible = flags & 1 != 0;
        let mut tracks = crate::model::Tracks::default_for(1, 1);
        for tp in TrackProp::ALL {
            let base = r_i32(&mut ar)?;
            if !tp.in_range(base) {
                return Err(SceneIoError::Corrupt("track base"));
            }
            let key_count = ar.varint()? as usize;
            if key_count > MAX_SCENE_FRAMES as usize {
                return Err(SceneIoError::TooLarge("keys"));
            }
            let mut keys = Vec::with_capacity(key_count);
            let mut prev: Option<u32> = None;
            for _ in 0..key_count {
                let frame = ar.varint()?;
                if frame >= MAX_SCENE_FRAMES {
                    return Err(SceneIoError::Corrupt("key frame"));
                }
                if let Some(p) = prev {
                    if frame <= p {
                        return Err(SceneIoError::Corrupt("key order"));
                    }
                }
                prev = Some(frame);
                let v = r_i32(&mut ar)?;
                if !tp.in_range(v) {
                    return Err(SceneIoError::Corrupt("key value"));
                }
                let tween = Tween::from_code(ar.u8()?).ok_or(SceneIoError::Corrupt("tween"))?;
                if tp.hold_only() && tween != Tween::Hold {
                    return Err(SceneIoError::Corrupt("tween"));
                }
                keys.push(crate::model::Key { frame, v, tween });
            }
            *tracks.get_mut(tp) = Track { base, keys };
        }
        actors.push(Actor { id, name, prop, mode, pin_to, visible, tracks });
    }
    // Pin validation needs the full actor list: parent exists and is unpinned (one level).
    for a in &actors {
        if let Some(pin) = a.pin_to {
            let parent = actors.iter().find(|p| p.id == pin).ok_or(SceneIoError::Corrupt("pin"))?;
            if parent.pin_to.is_some() {
                return Err(SceneIoError::Corrupt("pin"));
            }
        }
    }

    let scene = Scene {
        w,
        h,
        fps,
        frame_count,
        background,
        loop_a,
        loop_b,
        cast: cast_v,
        actors,
        prop_ids: IdGen::starting_at(max_prop_id.saturating_add(1)),
        actor_ids: IdGen::starting_at(max_actor_id.saturating_add(1)),
    };

    // Semantic integrity: the reconstruction must hash to the stored hash.
    if scene.content_hash() != stored_hash {
        return Err(SceneIoError::Corrupt("content hash mismatch"));
    }
    Ok((scene, playhead))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SceneSession;

    fn scripted(script: &str) -> SceneSession {
        let mut s = SceneSession::empty();
        s.run_script(script).expect("script runs");
        s
    }

    fn full_scene() -> SceneSession {
        scripted(
            "NewScene(24,16,25000); SetFrameCount(30); SetBackground(#08101820); SetLoop(2,20);\
             GenProp(6,4,3,9); SetCycleAll(1, 2); SetPropStyle(1, cleanedge);\
             GenPropSolid(5,5,#80FF4080);\
             PlaceActorAt(1, 6, 6); PlaceActorAt(2, 12, 8); PlaceActorAt(2, 20, 4);\
             SetPinTo(3, 2); SetActorMode(1, posing); RenameActor(1, hero);\
             SetKey(1, x, 0, 2); SetKeyTween(1, x, 10, 20, easeinout); SetKey(1, pose, 4, 2);\
             SetKey(2, rot, 0, 0); SetKey(2, rot, 25, 270000); SetKey(2, opacity, 9, 128);\
             SetBase(3, scale, 2500); SetKey(3, fliph, 7, 1); SetActorVisible(3, false)",
        )
    }

    #[test]
    fn roundtrip_preserves_everything() {
        let s = full_scene();
        let bytes = save_to_bytes(&s.scene, 13);
        let (back, playhead) = load_from_bytes(&bytes, usize::MAX).expect("loads");
        assert_eq!(playhead, 13);
        assert_eq!(back.content_hash(), s.scene.content_hash());
        // Composite equality across the whole range, not just the model hash.
        let mut c1 = crate::compose::TransformCache::new(1 << 24);
        let mut c2 = crate::compose::TransformCache::new(1 << 24);
        for f in 0..back.frame_count {
            assert_eq!(
                crate::compose::scene_frame(&s.scene, &mut c1, f).content_hash(),
                crate::compose::scene_frame(&back, &mut c2, f).content_hash(),
                "frame {f}"
            );
        }
    }

    #[test]
    fn deterministic_and_stable_bytes() {
        let s = full_scene();
        let b1 = save_to_bytes(&s.scene, 0);
        let b2 = save_to_bytes(&s.scene, 0);
        assert_eq!(b1, b2, "same scene ⇒ identical bytes");
        let (back, _) = load_from_bytes(&b1, usize::MAX).unwrap();
        assert_eq!(save_to_bytes(&back, 0), b1, "save→load→save is byte-stable");
    }

    #[test]
    fn dedup_shares_dictionary_tiles() {
        // Two solid props with identical art → the dictionary carries the tile once.
        let s = scripted(
            "NewScene(64,64,12500); GenPropSolid(32,32,#334455FF); GenPropSolid(32,32,#334455FF)",
        );
        let bytes = save_to_bytes(&s.scene, 0);
        assert!(
            bytes.len() < 32 * 32 * 4,
            "duplicate art dedups + compresses: {} bytes",
            bytes.len()
        );
    }

    #[test]
    fn corrupt_matrix() {
        let s = full_scene();
        let good = save_to_bytes(&s.scene, 0);

        assert!(matches!(load_from_bytes(&[0u8; 30], 1 << 30), Err(SceneIoError::BadMagic)));

        let mut bad_crc = good.clone();
        bad_crc[40] ^= 0xFF;
        assert!(matches!(
            load_from_bytes(&bad_crc, 1 << 30),
            Err(SceneIoError::Container(container::IoError::Corrupt("crc mismatch")))
        ));

        for cut in [1usize, 13, 60] {
            assert!(load_from_bytes(&good[..good.len() - cut], 1 << 30).is_err());
        }

        // Over-budget dictionary refused before materializing.
        assert!(matches!(
            load_from_bytes(&good, 0),
            Err(SceneIoError::TooLarge("memory budget"))
        ));
    }

    #[test]
    fn loader_rejects_semantic_corruption() {
        // Craft a file with a hold-only track carrying a linear tween by editing the model
        // through a bypass: serialize, then flip the tween byte of actor 3's fliph key.
        // (Cheaper and more honest: build via the session, save, and binary-patch — but the
        // tween byte's offset is format-dependent; instead build an invalid SCENE directly.)
        let mut s = full_scene();
        // Reach into the model (test-only) to force an illegal state, then save: the SAVE is
        // honest (it writes what it's given), the LOAD must refuse.
        let a = s.scene.actor_mut(3).unwrap();
        a.tracks.get_mut(TrackProp::FlipH).keys[0].tween = Tween::Linear;
        let bytes = save_to_bytes(&s.scene, 0);
        assert!(matches!(load_from_bytes(&bytes, 1 << 30), Err(SceneIoError::Corrupt("tween"))));

        let mut s2 = full_scene();
        let a = s2.scene.actor_mut(2).unwrap();
        a.tracks.get_mut(TrackProp::Scale).base = 99_999; // out of range
        let bytes2 = save_to_bytes(&s2.scene, 0);
        assert!(matches!(
            load_from_bytes(&bytes2, 1 << 30),
            Err(SceneIoError::Corrupt("track base"))
        ));

        let mut s3 = full_scene();
        s3.scene.actor_mut(3).unwrap().pin_to = Some(999); // dangling
        let bytes3 = save_to_bytes(&s3.scene, 0);
        assert!(matches!(load_from_bytes(&bytes3, 1 << 30), Err(SceneIoError::Corrupt("pin"))));
    }

    #[test]
    fn compact_envelope_roundtrip() {
        let s = full_scene();
        let plain = save_to_bytes(&s.scene, 5);
        let compact = makapix_codec::mkpx_compact::compress(&plain);
        assert!(makapix_codec::mkpx_compact::is_compact(&compact));
        let opened = makapix_codec::mkpx_compact::open(&compact).unwrap();
        let (back, playhead) = load_from_bytes(&opened, usize::MAX).unwrap();
        assert_eq!(playhead, 5);
        assert_eq!(back.content_hash(), s.scene.content_hash());
    }
}
