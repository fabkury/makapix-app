# Korean (Hangul) pixel fonts that could be bundled in a pixel-art editor (as of 2026-11-26)

Research notes. "Verified" means I read it on the primary source (repo README / LICENSE / author's page) during this
session; anything else is marked as secondary or as a gap. GitHub dates/versions come from the GitHub REST API
queried on 2026-11-26. I did NOT download or open any font file, so every statement about formats, on-grid outlines
and glyph counts is what the author's page says, not something measured.

## Which Korean pixel fonts have licenses that clearly permit bundling, format conversion, and redistribution of converted data in a public repo?

### Takeaway
Nine families clear the bar on license text alone: Galmuri (only Galmuri14 at 15 px and Galmuri11 Bold/Condensed are
new versus Fusion Pixel), NeoDunggeunmo / Pro (16 px), Mulmaru + ThinMulmaru (12 px), MaruMinya Hangul (12 px),
DenkiChip Hangul (12 px, 10 px wide), HBIOS-SYS (16 px), Dalmoori (8 px, Apache-2.0), LanaPixel (11 px, OFL or CC BY),
and the leedheo/hurss DOS set (16 px + one 24 px, MIT, but with a provenance problem). The realistic menu is therefore
8, 11, 12, 15, 16 and 24 px; I found nothing free and clearly licensed at 7, 9, 14 or 20 px.

### Cited Findings

#### A. Catalog of candidates with a permissive license (verified on primary source unless noted)

**1. Galmuri (갈무리) family** — Lee Minseo (quiple)
- URLs: [repo](https://github.com/quiple/galmuri), homepage https://galmuri.quiple.dev — [GitHub API](https://api.github.com/repos/quiple/galmuri)
- Sizes (the number in the name is NOT the pixel size): Galmuri7 = 8 px, Galmuri9 = 10 px, Galmuri11 = 12 px, Galmuri11 Bold = 12 px, Galmuri11 Condensed = 12 px, Galmuri14 = 15 px — [README](https://raw.githubusercontent.com/quiple/galmuri/main/README.md)
- Style: plain gothic (sans), described by the author as "Bitmap fonts inspired by the font design from Nintendo DS." — [README](https://raw.githubusercontent.com/quiple/galmuri/main/README.md)
- Coverage per README table: Galmuri14 / 11 / 9 have Hangul syllables (marked supported, no count), kana, and 6,355 hanja (JIS X 0208); Galmuri11 Bold has Hangul but no kana and no hanja; Galmuri11 Condensed has Hangul + kana, no hanja; Galmuri7 has a reduced Hangul set (the fetch summary reported "4,358 syllables (Adobe-KR-0 and -1)"; a README footnote I grepped says "Only 2,780 Hangul Syllables included in Adobe-KR-0" — I could not tell which column that footnote attaches to) — [README](https://raw.githubusercontent.com/quiple/galmuri/main/README.md)
- License: SIL OFL 1.1, "Copyright © 2019–2025 Lee Minseo (quiple@quiple.dev)". The header I read declares NO Reserved Font Name. — [ofl.md](https://raw.githubusercontent.com/quiple/galmuri/main/ofl.md)
- Maintenance: latest release v2.40.4 on 2026-07-12 (single asset `Galmuri-v2.40.4.zip`), last push 2026-10-29, 475 stars — [GitHub API](https://api.github.com/repos/quiple/galmuri/releases/latest)
- Fusion Pixel overlap: YES. Fusion Pixel's README says Galmuri "提供 8、10、12 像素韩语相关字形" (provides Korean glyphs at 8, 10, 12 px) — [Fusion README](https://raw.githubusercontent.com/TakWolf/fusion-pixel-font/master/README.md). The files vendored in its `assets/fonts/galmuri` folder are `Galmuri7.ttf`, `Galmuri9.ttf`, `Galmuri11.ttf`, `GalmuriMono7.ttf` — [Fusion repo folder](https://github.com/TakWolf/fusion-pixel-font/tree/master/assets/fonts/galmuri)
- So NOT already covered: Galmuri14 (15 px), Galmuri11 Bold (12 px), Galmuri11 Condensed (12 px).

**2. NeoDunggeunmo (Neo둥근모), NeoDunggeunmo Code, NeoDunggeunmo Pro** — Eunbin Jeong (Dalgona.)
- URLs: https://neodgm.dalgona.dev, [neodgm/neodgm](https://github.com/neodgm/neodgm), [neodgm/neodgm-pro](https://github.com/neodgm/neodgm-pro)
- Size: built on the DOS 8x16 / 16x16 cell, i.e. 16 px; Pro "breaks the 8x16, 16x16 pixel frame" with per-glyph widths and kerning (proportional) — [neodgm-pro README](https://raw.githubusercontent.com/neodgm/neodgm-pro/main/README.md)
- Style: rounded-corner sans ("둥근모꼴 특유의 모서리가 둥근 산세리프 스타일"), the classic Korean DOS / LED-signboard look; Latin and digits were newly designed because the original's Latin was judged unattractive — [project site](https://neodgm.dalgona.dev/)
- Formats: TTF / WOFF / WOFF2 only in releases (`neodgm.ttf`, `neodgm_code.ttf`, `NeoDunggeunmoPro-Regular.ttf`); the repo holds sources built with the author's PixelFont tool. No BDF in the release assets. — [GitHub API](https://api.github.com/repos/neodgm/neodgm/releases/latest), [README](https://raw.githubusercontent.com/neodgm/neodgm/main/README.md)
- License: SIL OFL 1.1 with Reserved Font Names "Neo둥근모", "Neo둥근모 Code", "NeoDunggeunmo", "NeoDunggeunmo Code" — [LICENSE.txt](https://raw.githubusercontent.com/neodgm/neodgm/main/LICENSE.txt). Site wording: free to "사용, 수정, 임베드, 및 재배포" (use, modify, embed, redistribute) commercially or not; reselling the font for money is prohibited — [project site](https://neodgm.dalgona.dev/)
- Maintenance: NeoDunggeunmo v1.601 released 2026-03-18 (active); Pro v1.020 released 2022-05-25, no push since — [GitHub API](https://api.github.com/repos/neodgm/neodgm-pro/releases/latest)
- Fusion Pixel overlap: none (not in its upstream list) — [Fusion README](https://raw.githubusercontent.com/TakWolf/fusion-pixel-font/master/README.md)

**3. Mulmaru (물마루) and Mulmaru Mono** — Mushsooni
- URLs: [mushsooni/mulmaru](https://github.com/mushsooni/mulmaru), https://mushsooni.github.io/
- Size: 12 px (9 pt) "또는 그 배수" (or multiples). Mulmaru is proportional, Mulmaru Mono fixed-width. — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- Style: "굵고 부드러운" (bold and soft): same size as Galmuri11 but with thick vertical strokes and rounded corners like DungGeunMo — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- Coverage: 11,937 glyphs = 11,172 Hangul syllables, ASCII 95, compatibility jamo 51, Latin-1 Supplement 77, Greek/Coptic 49, Cyrillic 65, hiragana 88, katakana 90, 7 CJK ideographs, 243 symbols — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- Formats: TrueType outlines generated by Pixel Font Maker, OpenType and webfonts added with FontForge; the `.pfp` source (JSON bitmap project for Pixel Font Maker) is published too — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- License: SIL OFL 1.1, "Copyright (c) 2025, Mushsooni", Reserved Font Names "물마루", "물마루 Mono", "Mulmaru", "Mulmaru Mono" — [LICENSE](https://raw.githubusercontent.com/mushsooni/mulmaru/main/LICENSE). README: free to use, modify, embed, redistribute commercially or not; selling the font alone is prohibited — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- Maintenance: last push 2026-01-08, 67 stars — [GitHub search API](https://api.github.com/search/repositories?q=korean+pixel+font)
- Fusion Pixel overlap: none.

**4. ThinMulmaru (얇은물마루)** — BinRecycle
- URL: [BinRecycle/ThinMulmaru](https://github.com/BinRecycle/ThinMulmaru)
- 12 px derivative of Mulmaru with the heavy strokes thinned; same SIL OFL as the original — [README](https://raw.githubusercontent.com/BinRecycle/ThinMulmaru/main/README.md)
- Last push 2026-09-09, 2 stars — [GitHub search API](https://api.github.com/search/repositories?q=%ED%94%BD%EC%85%80+%ED%8F%B0%ED%8A%B8)

**5. x12y12pxMaruMinyaHangul (마루미냐 한글)** — Lee Minseo (quiple), extending hicc's Japanese font x12y12pxMaruMinya
- URLs: [repo](https://github.com/quiple/x12y12pxMaruMinyaHangul), demo https://blog.quiple.dev/font/maruminya-hangul
- Size / style: 12 px "둥근고딕" (rounded gothic) Korean + Japanese pixel font — [GitHub search API description](https://api.github.com/search/repositories?q=%ED%94%BD%EC%85%80+%ED%8F%B0%ED%8A%B8)
- Coverage: all 11,172 Hangul syllables, KS X 1001 (excluding hanja), KS X 1003, and all of JIS X 0201 and JIS X 0208 — [README](https://raw.githubusercontent.com/quiple/x12y12pxMaruMinyaHangul/main/README.md)
- License: SIL OFL 1.1; © 2026 Lee Minseo and © 2026 The x12y12pxMaruMinya Project Authors. README table: commercial use allowed; embedding in games/software allowed; attribution "필수 아님" (not required); modification and redistribution allowed, modified redistributions must adopt OFL-1.1; selling the font file alone prohibited — [README](https://raw.githubusercontent.com/quiple/x12y12pxMaruMinyaHangul/main/README.md)
- Tools named: BitHangul, Bits'N'Picas, FontForge, fontTools — [README](https://raw.githubusercontent.com/quiple/x12y12pxMaruMinyaHangul/main/README.md)
- Maintenance: last push 2026-10-21 (new in 2026) — [GitHub search API](https://api.github.com/search/repositories?q=%ED%94%BD%EC%85%80+%ED%8F%B0%ED%8A%B8)

**6. x10y12pxDenkiChipHangul (전기칩 한글)** — Lee Minseo (quiple), extending hicc's x8y12pxDenkiChip
- URLs: [repo](https://github.com/quiple/x10y12pxDenkiChipHangul), demo https://blog.quiple.dev/font/denkichip-hangul
- Size / style: 12 px tall, compact and bold ("A compact 12px bold Korean and Japanese pixel font"); the name implies a 10 px wide Hangul cell — [GitHub search API description](https://api.github.com/search/repositories?q=hangul+pixel+font)
- Coverage: Latin, Hangul, hiragana, katakana, symbols; "4,358 Hangul syllables from Adobe-KR-0 and Adobe-KR-1" (NOT the full 11,172); all 2,965 JIS Level 1 kanji — [README](https://raw.githubusercontent.com/quiple/x10y12pxDenkiChipHangul/main/README.md)
- Formats: "The build outputs OTF, TTF, WOFF2, and BDF font files"; the TTF also carries 1-bit `EBDT`/`EBLC` bitmap strikes at 12, 24, 36, 48, 60 ppem — [README](https://raw.githubusercontent.com/quiple/x10y12pxDenkiChipHangul/main/README.md)
- License: SIL OFL 1.1, Copyright 2026 Lee Minseo and The x8y12pxDenkiChip Project Authors — [README](https://raw.githubusercontent.com/quiple/x10y12pxDenkiChipHangul/main/README.md)
- Maintenance: last push 2026-11-03, 33 stars — [GitHub search API](https://api.github.com/search/repositories?q=hangul+pixel+font)

**7. HBIOS-SYS** — Lee Minseo (quiple)
- URL: https://hbios.quiple.dev/ (links to a GitHub repo, `quiple/hbios-sys` per the CDN path on the page)
- Size / style: 16 px ("16픽셀 크기와 그 배수에서 가장 명확하게 표시"); modeled on the Korean MS-DOS system font; Latin based on VileR's IBM EGA 8x14; monospaced plus a separate proportional TTF — [HBIOS-SYS page](https://hbios.quiple.dev/)
- Coverage: all 11,172 Hangul syllables — [HBIOS-SYS page](https://hbios.quiple.dev/)
- Formats: TTF, WOFF2 and BDF downloads — [HBIOS-SYS page](https://hbios.quiple.dev/)
- License: MIXED. Glyphs taken from IBM EGA 8x14 (© 2015-2020 VileR) are CC BY-SA 4.0 (attribution + share-alike); all other glyphs (© 2022-2024 Lee Minseo) are SIL OFL 1.1 — [HBIOS-SYS page](https://hbios.quiple.dev/)
- Page shows version 1.046.

**8. Dalmoori (달무리)** — RanolP
- URLs: [RanolP/dalmoori-font](https://github.com/RanolP/dalmoori-font), https://ranolp.github.io/dalmoori-font/
- Size / style: 8x8, heavily simplified strokes, readability first; covers all modern Hangul ("현대 한글 전체를 지원") — [README](https://raw.githubusercontent.com/RanolP/dalmoori-font/main/README.md)
- License: Apache-2.0 ("달무리는 Apache 2.0으로 배포됩니다") — [README](https://raw.githubusercontent.com/RanolP/dalmoori-font/main/README.md)
- Maintenance: last push 2022-04-22, 112 stars (dormant) — [GitHub search API](https://api.github.com/search/repositories?q=hangul+pixel+font)
- References the author lists: Galmuri M, Galmuri9, Silver, Misaki Gothic, NeoDunggeunmo, D2Coding, Tiny — [README](https://raw.githubusercontent.com/RanolP/dalmoori-font/main/README.md)

**9. DOS-style collection: DOSMyungjo (도스명조), DOSGothic (도스고딕), DOSSaemmul (도스샘물), DOSIyagiBoldface (도스이야기), DOSPilgi (도스필기), Sam3KRFont (삼국지3글꼴), MiraeroNormal (미래로)** — leedheo / hurss
- URLs: [hurss/fonts](https://github.com/hurss/fonts) (stated original source), [leedheo/fonts](https://github.com/leedheo/fonts) (identical README); bundle `fonts_220507.zip`
- Sizes: BDF "(16pt)" for the DOS fonts; MiraeroNormal's BDF is 24x24 — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Styles: myeongjo (serif), gothic, Saemmul, Iyagi bold, handwriting (Pilgi), the Korean "Romance of the Three Kingdoms III" game font — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Formats: TTF and BDF — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Coverage: Basic Latin, Hangul Jamo, compatibility jamo, Hangul Syllables, CJK ideographs (KS X 1001 + optional KS X 1002 + JIS X 0213:2004); Sam3KRFont has no hanja; MiraeroNormal covers Unicode 1.1 without CJK ideographs — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- License: "해당 글꼴들은 MIT 라이선스에 기반을 둡니다" (based on the MIT License; changed to MIT in v0.2, 2016-08-19). FAQ: usable in paid products with the source credited; corporate commercial use "임베딩 포함" (including embedding) is allowed; requested credit form: "글꼴(폰트)로 도스샘물체(leedheo 제작)를 사용하였습니다"; source to cite is https://github.com/hurss/fonts — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Maintenance: final version 1.0 on 2022-05-07; the author states no more fonts will be made and modification / new-font requests are not accepted — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Provenance: "비트맵 데이터를 추출하여 도스 스타일 글꼴을 만들었습니다" (made by extracting bitmap data); hanja extracted from jiskan16 and DOS Simplified/Traditional Chinese fonts — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- noonnu lists Sam3KRFont with print/web/video/embedding/packaging/BI all allowed and says modification, duplication and redistribution are permitted, sale of the font file prohibited (secondary) — [noonnu](https://noonnu.cc/en/font_page/241)

**10. LanaPixel** — eishiya
- URL: [OpenGameArt](https://opengameart.org/node/114657)
- Size: designed for 11 px, integer scaling only; about 19,400 characters, of which roughly 11k are Hangul; a NoKorean build exists (search-result summary of the OGA page and the author's Reddit post; I did not open the pages themselves) — [OpenGameArt](https://opengameart.org/node/114657)
- License: listed as CC-BY 4.0; the author says it may alternatively be used under the SIL OFL, licensee's choice (search-result summary) — [OpenGameArt](https://opengameart.org/node/114657); a Sandoll Cloud listing labels it OFL but shows CC0 text, which is inconsistent — [Sandoll Cloud](https://www.sandollcloud.com/free-font/22251/LanaPixel)

**11. Silver** — Poppy Works
- URL: https://poppyworks.itch.io/silver
- License: CC BY 4.0, free for personal and commercial use "as long as it's attributed to Poppy Works"; productions whose budget "exceeds $100,000 USD in total spend or earnings" are asked to contact the author for a license — [itch.io](https://poppyworks.itch.io/silver)
- Format: single `Silver.ttf` (3.5 MB); the page does not state the pixel size or Hangul count; status "In development", latest devlog 2024-05-20, CJK still being filled in — [itch.io](https://poppyworks.itch.io/silver)

**12. IyagiGGC (이야기 굵은체 복각)** — PJW48 (Juwan Park)
- URL: https://pjw48.net/iyagiggc/
- Revival of the bold Hangul + myeongjo Latin font of the DOS terminal program Iyagi 5.3; all 11,172 syllables plus old jamo reproduced; TTF and WOFF (full-width and half-width versions), OTF withdrawn due to errors — [project page](https://pjw48.net/iyagiggc/)
- License: the page has a "사용권" section that my fetch truncated before reaching; fontmeme tags it "무료 상업용 / 무료" (secondary) — [fontmeme](https://fontmeme.com/ktype/free-pixel-fonts/)

#### B. Smaller / weaker candidates surfaced by GitHub search (descriptions only, READMEs not readable)
- `spotky1004/font-korean-7x7`: "7x7 픽셀 한글 폰트 입니다, 허가 없이 자유롭게 사용 가능" (7x7 Korean pixel font, free to use without permission); no license file detected, last push 2022-06-27 — [GitHub search API](https://api.github.com/search/repositories?q=korean+pixel+font)
- `sawalk/MapleSaemmul`: "a korean bitmap font inspired by MapleStory DS", OFL-1.1, last push 2026-08-28 — [GitHub search API](https://api.github.com/search/repositories?q=korean+bitmap+font)
- `Hansha2011/NanoHangulHei`: 12x12, states SIL OFL 1.1, but "Dotum을 기반으로 하는 픽셀화된 글꼴" (pixelized from Dotum, a Microsoft/Hanyang system font) and no license file detected — [README](https://raw.githubusercontent.com/Hansha2011/NanoHangulHei/main/README.md)
- `yangpa-onyon/Mallangche` (말랑체): MIT, full 11,172 syllables, but anti-aliased and distributed only as PNG sheets — fails the 1-bit requirement — [README](https://raw.githubusercontent.com/yangpa-onyon/Mallangche/master/README.md)
- `TakWolf/pixel-glyphs-hangul-syllables` ("AC00..D7AF; Hangul Syllables", MIT, pushed 2026-11-23), `TakWolf/jelly-pixel-font` (round style, pan-CJK) and `pixel-font-studio/fusion-bold-pixel-font` are siblings of the font already shipped; whether they contain original Hangul was not checked — [GitHub search API](https://api.github.com/search/repositories?q=hangul+pixel+font)
- `ageldama/x11-hangul-fonts-from-20th-century` (X11 PCF/BDF collection) and `chocolatemelt/baekmuk`: no license detected by GitHub — [GitHub search API](https://api.github.com/search/repositories?q=hangul+bdf)

#### C. Paid / restricted (fail the constraints)
- DNF Bit Bit v2 (던파 비트비트체 v2), Nexon Korea / Neople: free, commercial use and bundling allowed, modified redistribution forbidden (terms quoted in the next section) — [Sandoll Cloud](https://www.sandollcloud.com/free-font/19491/DNF-Bit-Bit-v2)
- Sandoll Cloud's pixel theme lists 22 fonts; only Galmuri11 and DNF Bit Bit v2 carry the free label among the 12 visible. Subscription/commercial ones: SD 픽셀쁘띠공주, SD 픽셀굿밤, 타이포_픽셀고딕27, 타이포_픽셀명조36, Cat 까칠한토끼로망스, Cat 말랑한꼬부기로망스, Dain 도트앤픽셀, Egg9LoveBitmap, AR TXPixel3D20GB, Yoon px 아케이드 — [Sandoll Cloud theme](https://www.sandollcloud.com/font-themes/314). Prices were not shown.

### Inferences
- OFL 1.1 defines a "Modified Version" as including one made "by changing formats or by porting the Font Software to a new environment", and permits bundling and redistributing modified versions with software if the copyright notice and license travel with each copy ([OFL text in Galmuri's ofl.md](https://raw.githubusercontent.com/quiple/galmuri/main/ofl.md)). So converted data from the OFL fonts is a Modified Version: allowed in the repo and the app, must stay under OFL with the notice, and must not be presented to users under a Reserved Font Name.
- Reserved Font Names are declared by NeoDunggeunmo and Mulmaru but not by Galmuri (header I read). A converted bitmap shown in a font picker as "Mulmaru" or "NeoDunggeunmo" is exactly the "primary font name as presented to the users" that condition 3 restricts; Fusion Pixel avoids this by using its own name. This is my reading, not legal advice — asking those two authors for written permission to keep the name is the clean route.
- By size, what is new versus what ships today (8/10/12): 11 px (LanaPixel), 15 px (Galmuri14), 16 px (NeoDunggeunmo, Pro, HBIOS-SYS, DOS set), 24 px (MiraeroNormal). New styles at an existing size: 12 px bold-rounded (Mulmaru), thin (ThinMulmaru), rounded (MaruMinya Hangul), compact bold (DenkiChip Hangul), Galmuri11 Bold/Condensed; 8 px alternative (Dalmoori).
- HBIOS-SYS's CC BY-SA 4.0 Latin glyphs bring a share-alike term; converting only its OFL Hangul and pairing it with another Latin would avoid that.

### Gaps
- No free, clearly licensed Hangul pixel font found at 7, 9, 14 or 20 px. `font-korean-7x7` is the only 7 px lead and has no license file.
- Not researched at all (ran out of budget): Pixelroborobo 픽셀로보로보, Stardust 스타더스트, the original DungGeunMo distribution (ith.kr served a bot check), Hanterm / X11 `hanglg16` / `hanglm16` / `hanglm24`, Daewoo and Baekmuk bitmap BDF licenses, Iyagi / 8x4x4 johab font sets, 도깨비 fonts, GNU Unifont's Hangul (the unifoundry page loaded but I did not reach the design/license part), Kenney fonts, burpyfresh's itch.io fonts (Plain Pixel, Seven Fifteen, Polygothic — a search result says they added Korean; Fantasy Warrior is CC BY 4.0), 공유마당, Cafe24 / Nexon non-pixel families.
- NeoDunggeunmo's exact Hangul count and whether its TTF outlines are strictly on-grid: the README defers to the website's glyph list, which I did not open.
- Whether each TTF is an on-grid outline was not measured for any font; only DenkiChip Hangul states embedded bitmap strikes and a BDF.
- Galmuri BDF availability: not confirmed from the README lines I saw (the release is one zip).
- IyagiGGC license text, MapleSaemmul and font-korean-7x7 READMEs (404 on main/master) were not read.

## What does each license actually say, especially on modification and redistribution?

### Takeaway
The community fonts (OFL, Apache-2.0, MIT) all permit modification and redistribution of modified data; the one corporate font checked, DNF Bit Bit, shows the typical Korean pattern of "use, bundle and embed freely, but do not redistribute a modified font file", which rules out committing converted data.

### Cited Findings
- OFL fonts (Galmuri, NeoDunggeunmo, Mulmaru, ThinMulmaru, MaruMinya Hangul, DenkiChip Hangul, HBIOS-SYS Hangul): may be "bundled, redistributed and/or sold with any software, provided that each copy contains the above copyright notice and this license"; may not be sold by itself; modified versions may not use Reserved Font Names; must stay entirely under OFL — [OFL text](https://raw.githubusercontent.com/quiple/galmuri/main/ofl.md)
- MaruMinya Hangul states attribution is not required and that a modified redistribution must adopt OFL-1.1 — [README](https://raw.githubusercontent.com/quiple/x12y12pxMaruMinyaHangul/main/README.md)
- leedheo/hurss DOS fonts: MIT-based; commercial use and embedding allowed with a source credit (wording above). The repo README does not reproduce an MIT license text in the part I read — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Dalmoori: Apache-2.0 — [README](https://raw.githubusercontent.com/RanolP/dalmoori-font/main/README.md)
- DNF Bit Bit v2 (as reproduced by Sandoll Cloud; maker's page given as https://brand.nexon.com/ko/ci-brand-guidelines/typeface): "넥슨 서체는 ... 모든 사용자에게 무료로 제공되며 자유롭게 사용 및 배포하실 수 있습니다." / "(상업적인 용도로 사용 가능) 단, 임의로 폰트 파일을 수정 편집하여 재배포할 수 없습니다." (commercial use allowed, but the font file may not be arbitrarily modified/edited and redistributed) / selling the font is prohibited; it may be bundled with other software or used as an embedded font if the copyright notice is included. OFL row: "비해당" (not applicable) — [Sandoll Cloud](https://www.sandollcloud.com/free-font/19491/DNF-Bit-Bit-v2)
- Silver: CC BY 4.0 with attribution to Poppy Works, plus the $100,000 budget request — [itch.io](https://poppyworks.itch.io/silver)

### Inferences
- DNF Bit Bit fails specifically on the conversion step: bundling the original TTF would be allowed, a converted bitmap in a public repo is a modified file being redistributed.
- Silver's $100,000 clause sits beside a CC BY 4.0 grant, which CC BY itself does not condition on budget; the combination is ambiguous and worth avoiding or clarifying with the author.
- CC BY 4.0 (LanaPixel, Silver) requires attribution to travel with the font data; for LanaPixel choosing the OFL option aligns it with the rest of the bundle.

### Gaps
- I did not read Nexon's own typeface page; the DNF Bit Bit terms are quoted via Sandoll Cloud, which warns terms may change.
- DNF Bit Bit's native pixel size was not found.
- No noonnu license tables were read for the other fonts (the noonnu search URL returned marketplace items, not the pixel filter).

## Which ones offer a visibly different style from Galmuri's plain gothic?

### Takeaway
The clearest departures are the DOS set (the only free myeongjo/serif and handwriting bitmaps found), the DungGeunMo lineage (rounded 16 px), and Mulmaru / DenkiChip Hangul (heavy 12 px).

### Cited Findings
- Myeongjo/serif: DOSMyungjo; handwriting: DOSPilgi; Saemmul: DOSSaemmul; bold Iyagi: DOSIyagiBoldface and IyagiGGC; game font: Sam3KRFont — [hurss README](https://raw.githubusercontent.com/hurss/fonts/master/README.md), [IyagiGGC](https://pjw48.net/iyagiggc/)
- Rounded-corner 16 px sans, monospaced (NeoDunggeunmo) or proportional with kerning (Pro) — [project site](https://neodgm.dalgona.dev/)
- Korean MS-DOS system look at 16 px: HBIOS-SYS — [page](https://hbios.quiple.dev/)
- Bold + soft 12 px: Mulmaru, explicitly made because nothing was "smaller than DungGeunMo's 16 px, thicker than Galmuri" — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- Rounded gothic 12 px: MaruMinya Hangul; compact bold 12 px: DenkiChip Hangul — [GitHub search API](https://api.github.com/search/repositories?q=hangul+pixel+font)
- Minimal 8x8: Dalmoori — [README](https://raw.githubusercontent.com/RanolP/dalmoori-font/main/README.md)

### Inferences
- Style descriptions are the authors' words; I viewed no specimen images, so "visibly different" is unconfirmed by eye.

### Gaps
- No free decorative Hangul pixel font was verified. Paid ones exist on Sandoll Cloud (타이포_픽셀명조36, SD 픽셀 series).

## Are there curated lists that reveal additional candidates?

### Takeaway
No single good list turned up; GitHub repository search and Sandoll Cloud's pixel theme were the most productive, and fontmeme / freekoreanfont.com tag pages are usable secondary indexes.

### Cited Findings
- fontmeme's Korean free-pixel listing surfaces DenkiChipHangul, MaruMinyaHangul, Dalmoori, Puzzle Sans (CAPRICO, tagged OFL) and IyagiGGC — [fontmeme](https://fontmeme.com/ktype/free-pixel-fonts/)
- freekoreanfont.com has a "Pixel" category with 4 entries, including Mulmaru and MaruMinya Hangul; the category page returned HTTP 429 — [Mulmaru entry](https://www.freekoreanfont.com/?p=875)
- Sandoll Cloud "픽셀 폰트" theme, 22 fonts (12 seen) — [Sandoll Cloud](https://www.sandollcloud.com/font-themes/314)
- Mulmaru's credits double as a lineage list: 둥근모꼴 (김중태), Galmuri, Yoon px 아케이드, PixelMplus, Fixedsys Excelsior, Pixel Operator, HBIOS-SYS, 이야기 굵은체 (PJW48), Tiny5 — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)

### Gaps
- Puzzle Sans (CAPRICO) was not investigated: pixel size and license unverified.
- noonnu's 픽셀 filter and Korean blog roundups were not reached; pages 2 of the Sandoll theme not seen.

## Any provenance concerns?

### Takeaway
Yes, and they scale with how "retro" the font is: the DOS set is openly extracted bitmap data from old commercial software relicensed as MIT by the extractor, while Galmuri, HBIOS-SYS and Mulmaru openly acknowledge commercial models but are redrawn or partly original.

### Cited Findings
- leedheo/hurss: fonts made "by extracting bitmap data"; hanja from jiskan16 and DOS Chinese fonts; Sam3KRFont is the font of the game 삼국지3 — [README](https://raw.githubusercontent.com/hurss/fonts/master/README.md)
- Galmuri: the author states that in Galmuri14/11/9 everything EXCEPT Latin-1, kana, kanji, some symbols and 2,355 Hangul syllables is his own creation (in Galmuri7, everything except Latin-1, kana, kanji and some symbols); Galmuri11 Bold and Condensed are entirely his own. He adds that this does not mean Nintendo owns rights in the rest, argues that bitmap fonts and typeface designs are generally not copyrightable in the US and Korea, and claims copyright only in the outline font files — [README](https://raw.githubusercontent.com/quiple/galmuri/main/README.md)
- HBIOS-SYS: "한글 MS-DOS의 시스템 글꼴을 본따 만들어진" (modeled on the Korean MS-DOS system font); original design credited to IBM (Latin) and Qnix Computer / Microsoft Korea (Hangul) — [page](https://hbios.quiple.dev/)
- NeoDunggeunmo: source font 둥근모꼴 was made by 김중태 in the 1990s and "퍼블릭 도메인으로 배포" (released as public domain), per the NeoDunggeunmo author — [neodgm-pro README](https://raw.githubusercontent.com/neodgm/neodgm-pro/main/README.md)
- Mulmaru: Hangul "mainly referenced" the design of the commercial Yoon px 아케이드 and was redesigned from a 10x6x4-set johab template; the README disclaims any relation to those authors and says it was made in compliance with Korean copyright and design-protection law, citing Supreme Court case 94누5632 — [README](https://raw.githubusercontent.com/mushsooni/mulmaru/main/README.md)
- IyagiGGC is a "복각" (reproduction) of the Iyagi 5.3 terminal program's font — [page](https://pjw48.net/iyagiggc/)
- NanoHangulHei is pixelized from Dotum — [README](https://raw.githubusercontent.com/Hansha2011/NanoHangulHei/main/README.md)
- MapleSaemmul is "inspired by MapleStory DS" — [GitHub search API](https://api.github.com/search/repositories?q=korean+bitmap+font)

### Inferences
- Ranked by provenance comfort (my judgment): cleanest are Galmuri11 Bold/Condensed (fully original per author), MaruMinya Hangul and DenkiChip Hangul (original Hangul on an OFL Japanese base), Dalmoori, NeoDunggeunmo (public-domain source, though that claim is second-hand); middle are Galmuri14 (same Nintendo DS caveat already accepted for 8/10/12), Mulmaru, HBIOS-SYS; weakest are the leedheo DOS set, IyagiGGC, NanoHangulHei, where the MIT/OFL label is applied by someone who extracted or traced another party's font.
- The DOS set is the only source of myeongjo and handwriting styles, so the style gain and the provenance risk come together.

### Gaps
- The public-domain status of 둥근모꼴 was not verified at the original author's site (bot check).
- No legal source was read on Korean bitmap-font copyright beyond the authors' own citations.
