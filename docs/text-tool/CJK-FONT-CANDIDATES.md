# CJK pixel font candidates: measurements and recommendation

Measured 2026-11-26 for the Text tool (ADR 0039, `DESIGN.md`). The 26 recommended fonts were
converted and bundled the same day (`tools/fonts/build_fonts.py --cjk`) and shipped in 1.16.0; the sizes in the tables
are the estimates made before converting, and the real files total 8.5 MB. This file records what
was measured so the choice can be revisited without redoing the work.

- **Source files** are not in this repository. They sit beside the VEXED and Fusion Pixel sources
  in the local font library, folder `pixel-fonts/cjk/` (`ja/`, `zh/`, `ko/`), with an index,
  specimen sheets, the raw measurement JSON and the two scripts under `cjk/_index/`.
- **Background research** (licenses, rejected fonts, fonts never examined):
  `reports/CJK pixel fonts for Text tool.md`.

## How the numbers were made

Each font file was opened with `cjk/_index/tools/inspect_fonts.py` (fontTools for TTF, a built-in
reader for BDF). Coverage is the count of code points the font maps, against these sets:

| Set | Size | Meaning |
|---|---|---|
| JIS L1 / L2 | 2,965 / 3,390 | JIS X 0208 kanji, levels 1 and 2 |
| GB L1 / L2 | 3,755 / 3,008 | GB 2312 hanzi, levels 1 and 2 (Simplified) |
| Big5 common / less | 5,401 / 7,652 | Big5 hanzi, frequent and less frequent (Traditional) |
| Hangul | 11,172 | all modern Hangul syllables |

"Exact source" says where lossless 1-bit glyphs come from: a BDF file, an embedded bitmap strike
at the native size, or outlines whose every point lies on the pixel grid. A mapped code point is
not proof of a good glyph; only the specimen strings were looked at by eye.

Size estimates use the `.mkf` cost measured on the shipped fonts: 9 bytes per glyph plus the
bitmap, deflating to about 42% in the APK. They are estimates, not converted files.

## Recommended for the app: 26 fonts

Estimated total: about 9.0 MB of font data, about 3.8 MB of download, and about 12 MB held in
memory after the font picker has been opened once (the picker loads every font and nothing is
released until the app exits).

### Japanese (12)

| Font | Native px | Style | Code points | JIS L1+L2 | Exact source | License | Est. size |
|---|---|---|---|---|---|---|---|
| k8x12 | 12 (8 wide) | narrow gothic | 7,170 | 2,965+3,390 | BDF | M+-style, unrestricted | 140 KB |
| Shinonome Mincho 12 | 12 | serif | 7,146 | 2,965+3,390 | strike | public domain | 174 KB |
| Shinonome Marumoji 12 | 12 | rounded handwriting | 7,146 | 2,965+3,390 | strike | public domain | 174 KB |
| MaruMinya 12 | 12 | rounded gothic | 7,533 | 2,965+3,390 | strike | OFL 1.1, no reserved name | shared with Korean |
| Shinonome Mincho 14 | 14 | serif | 7,146 | 2,965+3,390 | strike | public domain | 209 KB |
| Shinonome Gothic 16 | 16 | plain gothic | 7,146 | 2,965+3,390 | strike, on-grid | public domain | 262 KB |
| KH Dougenzaka 16 | 16 | bold serif | 7,263 | 2,965+3,390 | strike, on-grid | OFL 1.1 | 262 KB |
| KH Akihabara 16 | 16 | rounded | 7,263 | 2,965+3,390 | strike, on-grid | OFL 1.1 | 262 KB |
| KH Kabutochou 16 | 16 | heavy display | 7,264 | 2,965+3,390 | strike, on-grid | OFL 1.1 | 262 KB |
| Ayu Mincho 18 | 18 | serif | 7,221 | 2,965+3,390 | strike | public domain | 310 KB |
| Kappa 20 | 20 | gothic | 7,116 | 2,965+3,390 | strike | public domain | 361 KB |
| KH Hibiya 24 | 24 | serif | 7,623 | 2,965+3,390 | strike | OFL 1.1 | 528 KB |

### Chinese (9)

| Font | Native px | Style | Code points | GB L1+L2 | Big5 common+less | Exact source | License | Est. size |
|---|---|---|---|---|---|---|---|---|
| BoutiqueBitmap9x9 Bold | 10 | bold gothic | 13,157 | 3,755+2,108 | 5,401+2,139 | on-grid outline (12 glyphs off the grid, sampled) | OFL 1.1 | 256 KB |
| ChangBanDianSong 12 | 12 | bold Song (serif) | 15,099 | 3,755+3,008 | 5,401+3,171 | BDF | OFL 1.1 | 368 KB |
| Z Labs RoundPix 12 (listed as "RoundPix 12") | 12 | rounded | 13,301 | 3,755+3,008 | 5,401+2,641 | on-grid outline | OFL 1.1, reserved name | 324 KB |
| ChangBanDianSong 16 SC | 16 | bold Song, Simplified forms | 15,492 | 3,755+3,008 | 5,401+3,304 | BDF | OFL 1.1 | 559 KB |
| ChangBanDianSong 16 TC | 16 | bold Song, Traditional forms | 15,492 | 3,755+3,008 | 5,401+3,304 | BDF | OFL 1.1 | 559 KB |
| RenOuFangSong 16 | 16 | Fangsong, light | 13,809 | 3,755+3,008 | 5,401+2,479 | BDF | OFL 1.1 | 498 KB |
| QiuYeYuanTi 16 | 16 | rounded | 13,726 | 3,755+3,008 | 5,401+2,452 | BDF | OFL 1.1 | 495 KB |
| ShanWeiZhouHei 16 | 16 | heavy display, Simplified | 13,752 | 3,755+3,008 | 5,401+2,476 | BDF | OFL 1.1 | 496 KB |
| FashionBitmap16 | 16 | heavy display, Traditional | 9,001 | 2,784+1,259 | 5,401+920 | on-grid outline (its strike is blank) | OFL 1.1 | 325 KB |

The two ChangBanDianSong 16 files differ only in glyph forms, so they can be stored as one base
layer plus a small delta, as Fusion Pixel is. The 12 px file and the other 16 px fonts hold both
Simplified and Traditional characters in one file.

### Korean (5)

| Font | Native px | Style | Code points | Hangul | Exact source | License | Est. size |
|---|---|---|---|---|---|---|---|
| Galmuri11 Bold | 12 | bold | 12,695 | 11,172 | BDF | OFL 1.1, no reserved name | 309 KB |
| Galmuri11 Condensed | 12 | narrow | 13,143 | 11,172 | BDF | OFL 1.1, no reserved name | 320 KB |
| MaruMinya Hangul 12 | 12 | rounded | 19,106 | 11,172 | BDF | OFL 1.1, no reserved name | 466 KB |
| Galmuri14 | 15 | plain gothic | 19,222 | 11,172 | BDF | OFL 1.1, no reserved name | 619 KB |
| NeoDunggeunmo (listed as "Dunggeun 16") | 16 | rounded-corner retro | 12,506 | 11,172 | on-grid outline | OFL 1.1, reserved name | 451 KB |

MaruMinya Hangul contains every MaruMinya glyph (all 6,355 JIS kanji) plus Hangul, so one data
file can back both the Japanese and the Korean picker entry.

## In the local library, not recommended for the app yet: 14 fonts

| Font | Native px | Style | Coverage measured | License | Why it waits |
|---|---|---|---|---|---|
| DenkiChip 8x12 (ja) | 12 | compact bold | JIS L1 only (2,965) | OFL 1.1 | no level 2 kanji |
| K14 (ja) | 14 | gothic | 11,379 cps, full JIS | public domain | plain; first alternate if a 14 px gothic is wanted |
| KH Ningyouchou 16 (ja) | 16 | textbook | full JIS | OFL 1.1 | close to the gothic at this size |
| KH Hibiya 32 (ja) | 32 | serif | full JIS | OFL 1.1 | about 960 KB for one font |
| MaruMonica 12x16 (ja) | 16 | retro game | full JIS, 8,218 cps | author's custom license | author is moving it to OFL; wait for that edition |
| Z Labs Pixel 12 (zh) | 12 | gothic | full GB 2312, Big5 5,401+3,130 | OFL 1.1, reserved name | another plain gothic at a shipped size |
| Z Labs RoundPix 16 (zh) | 16 | rounded | full GB 2312, Big5 3,472+1,083 | OFL 1.1, reserved name | Traditional coverage thin; QiuYeYuanTi covers the style |
| ZhengGeDianHei 16 (zh) | 16 | gothic | full GB 2312, Big5 5,401+2,455 | OFL 1.1 | plain; first alternate for a 16 px gothic (also full JIS) |
| BaDingShiWeiTi 16 (zh) | 16 | flared | full GB 2312, Big5 5,401+2,481 | OFL 1.1 | reads close to RenOuFangSong at this size |
| MuzaiPixel 8x12 (zh) | 12 | narrow gothic | full GB 2312, Big5 5,401+3,886 | OFL 1.1, reserved name | dense and hard to read in the specimen |
| Mulmaru 12 (ko) | 12 | bold, soft | 11,172 Hangul | OFL 1.1, reserved name | close to Galmuri11 Bold |
| HBIOS-SYS 16 (ko) | 16 | DOS system look | 11,172 Hangul | OFL Hangul, CC BY-SA Latin | modeled on a Microsoft system font; share-alike Latin |
| DenkiChip Hangul 10x12 (ko) | 12 | compact bold | 4,365 Hangul | OFL 1.1 | under half of Hangul |
| Dalmoori (ko) | 8 | minimal | 11,172 Hangul | Apache-2.0 | rendered garbled at 8 px here; native size unresolved |

The downloaded archives hold more than these 40 (all 55 JF Dot and 15 KH Dot files, three k8x12
cuts, bold weights, the remaining hicc fonts, which have no kanji). Their measurements are in
`cjk/_index/measurements/`.

## Findings that correct the earlier research

- **Reserved names are rarer than reported.** The license files of the yzdnn fonts
  (ChangBanDianSong, RenOuFangSong, QiuYeYuanTi, ShanWeiZhouHei, ZhengGeDianHei, BaDingShiWeiTi),
  BoutiqueBitmap9x9 and FashionBitmap16 declare no Reserved Font Name. Among the 26, only Z Labs
  RoundPix 12 and NeoDunggeunmo do. The READMEs were not re-read for naming requests.
- **MaruMinya is OFL.** Its repository carries OFL 1.1 since version 1.500 (February 2026), which
  settles the conflict noted in the report.
- **"Unfinished" Chinese fonts are well covered.** Every yzdnn font maps all 6,763 GB 2312 hanzi
  and all 5,401 common Big5 hanzi.
- **DotGothic16 is not exact at 16 px.** It has no bitmap strike and its outlines are off the
  grid; the specimen shows uneven strokes. ZhengGeDianHei 16, derived from it, ships a BDF.

## Not verified

- Glyph quality beyond the specimen strings; whether any "unfinished" font still carries
  placeholder or Japanese-form glyphs at Chinese code points.
- Public-domain status of the JF Dot fonts other than Shinonome rests on the distributor's table.
- Coverage of 通用规范汉字表 (8,105) was not measured; no list was at hand.
