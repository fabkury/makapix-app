# Pan-CJK pixel fonts and cross-cutting licensing / technical questions

Research date: 2026-11-26. "Verified" means read from the primary source in this session (GitHub API / raw files, unifoundry.com, gnu.org, openfontlicense.org, wenq.org, openlab.ring.gr.jp). Anything known only from secondary sources or from the researcher's prior knowledge is labeled as such or placed under Gaps. Nothing here is legal advice.

## A1. Fusion Pixel Font: what is its state in late 2026?

### Takeaway
Fusion Pixel Font is alive and on a regular cadence (latest release 2026.11.10), still OFL 1.1 with no Reserved Font Name, and still ships ONLY 8, 10 and 12 px (no 16 px), each as monospaced and proportional. The upstream table has changed versus older releases: Simplified Chinese at 10/12 px now comes from Ark Pixel itself and no WenQuanYi-derived source is listed.

### Cited Findings
- Latest release tag `2026.11.10`, published 2026-11-09T20:53:07Z; repo last pushed 2026-11-25; 3,531 stars. — [GitHub API, releases/latest](https://api.github.com/repos/TakWolf/fusion-pixel-font/releases/latest)
- Release assets exist for exactly three sizes (8px, 10px, 12px), each in `monospaced` and `proportional`, and each in these formats: `bdf`, `pcf`, `otb`, `dfont`, `ms.bitmap.ttf`, `otf`, `ttf`, plus `woff`/`woff2` wrappers of otf and ttf. No 16 px asset exists. — [fusion-pixel-font releases](https://github.com/TakWolf/fusion-pixel-font/releases)
- README self-description: open-source pan-Latin and pan-CJK pixel font, "黑体" (gothic/sans) style; it is a "temporary transitional solution" for Ark Pixel Font, using Ark Pixel as base glyphs and metrics and filling gaps with other same-size fonts (hence "Fusion"/缝合). — [README](https://github.com/TakWolf/fusion-pixel-font/blob/master/README.md)
- Width modes (README): monospaced = half/full width cells, glyph height and line height confined to the em box, fewer characters supported, baseline slightly high; proportional = natural widths, kerning supported; README recommends proportional unless there is a special need. — [README](https://github.com/TakWolf/fusion-pixel-font/blob/master/README.md)
- Language-specific glyph versions (README): `latin`, `zh-Hans` (follows 通用规范汉字表), `zh-Hant` (traditional printing forms 舊字形), `zh-HK`, `zh-TW`, `ja` (常用漢字表 / 表外漢字字体表), `ko` (KS X 1001 / KS X 1002). README caveat: this is "still a patch-based font solution; you should not have particular expectations of the language-specific glyphs". — [README](https://github.com/TakWolf/fusion-pixel-font/blob/master/README.md)
- License: font under SIL OFL 1.1, build program under MIT. LICENSE-OFL header reads "Copyright (c) 2022, TakWolf (https://takwolf.com). This Font Software is licensed under the SIL Open Font License, Version 1.1." with no "with Reserved Font Name" clause. — [LICENSE-OFL](https://github.com/TakWolf/fusion-pixel-font/blob/master/LICENSE-OFL)
- Upstream fonts and licenses as listed in the README on 2026-11-26:
  - Ark Pixel Font (OFL-1.1): 10 and 12 px base glyphs and metrics.
  - 美咲フォント / Misaki ("untyped license, compatible with OFL-1.1", license text kept in `assets/fonts/misaki/misaki.txt`): 8 px Japanese kanji.
  - 美績点陣體 / MisekiBitmap (ItMarki, OFL-1.1): 8 px Simplified Chinese hanzi.
  - 精品點陣體7×7 / BoutiqueBitmap7x7 (scott0107000, OFL-1.1): 8 px Traditional Chinese hanzi.
  - 精品點陣體9×9 / BoutiqueBitmap9x9 (OFL-1.1): 10 px Traditional Chinese supplement.
  - 俐方體11號 / Cubic 11 (ACh-K, OFL-1.1): 12 px Traditional Chinese supplement.
  - Galmuri (quiple, OFL-1.1): 8, 10 and 12 px Korean glyphs.
  — [README, license table](https://github.com/TakWolf/fusion-pixel-font/blob/master/README.md)
- Coverage, 8 px proportional: 28,410 characters; CJK Unified Ideographs 14,719 / 20,992; Hangul Syllables 11,172 / 11,172; Hiragana 87/93; Katakana 90/96; GB2312 level 1 3,755/3,755, level 2 3,008/3,008 (total 7,277/7,445); Big5 common 5,401/5,401, less-common 4,803/7,652; Shift-JIS total 6,921/7,037; KS X 1001 total 7,830/8,226. — [info-8px-proportional](https://github.com/TakWolf/fusion-pixel-font/blob/master/docs/info-8px-proportional.md)
- Coverage, 10 px proportional: 25,918 characters; CJK Unified 10,687 / 20,992; Hangul 11,172 / 11,172; kana complete; GB2312 level 1 3,755/3,755, level 2 2,190/3,008 (total 6,596/7,445); Big5 common 5,401/5,401, less-common 2,168/7,652; Shift-JIS 7,005/7,037; KS X 1001 7,826/8,226. — [info-10px-proportional](https://github.com/TakWolf/fusion-pixel-font/blob/master/docs/info-10px-proportional.md)
- Coverage, 12 px proportional: 38,213 characters; CJK Unified 19,546 / 20,992; Ext A 1,777; Ext B 1,458; Hangul 11,172 / 11,172; kana complete; GB2312 level 1 3,755/3,755, level 2 2,972/3,008 (total 7,378/7,445); Big5 common 5,401/5,401, less-common 6,847/7,652 (total 12,593/13,461); Shift-JIS 7,005/7,037; KS X 1001 8,011/8,226. — [info-12px-proportional](https://github.com/TakWolf/fusion-pixel-font/blob/master/docs/info-12px-proportional.md)
- An algorithmic bold derivative exists: 缝合粗像素字体 / Fusion Bold Pixel Font (8/10/12 px), now under the `pixel-font-studio` GitHub organization; README warns "this is not a formal project, only for testing ... proof of concept". Bolding is a "shift right by 1 px and overlap, then carve the counter" algorithm. — [fusion-bold-pixel-font README](https://github.com/pixel-font-studio/fusion-bold-pixel-font/blob/master/README.md)
- TakWolf maintains Godot and Unity "pixel font localization sample" repos for Fusion Pixel (pushed 2026-10-28). — [TakWolf repos](https://github.com/TakWolf?tab=repositories)

### Inferences
- The 10 px size is the weakest of the three for Chinese: GB2312 level 2 is only 73% and Big5 less-common 28%, so rare-ish hanzi will fall through at 10 px but not at 8 or 12 px. (Counter-intuitively the 8 px size has fuller GB2312 than 10 px, because Miseki/Boutique 7x7/Misaki are complete sets.)
- Because Fusion is a patchwork, a "second style" at 8/12 px could be obtained by shipping the upstream fonts directly (Misaki, MisekiBitmap, BoutiqueBitmap 7x7/9x9, Cubic 11, Galmuri); they are separate designs only in their own script's range. Those belong to the single-script researchers.
- A bold face can be generated in-app from any 1-bit font with the same shift-and-overlap algorithm used by Fusion Bold, with no extra font data.

### Gaps
- Per-language release artifacts (how `ja` / `zh_hans` / `zh_hant` / `ko` flavors are packaged inside each zip) were not unpacked in this session.
- The Misaki license text was not re-read here (the Japanese-only researcher should quote it); the README only characterizes it as "untyped, OFL-compatible".
- Whether older Fusion releases' upstreams (which the app may have converted) differ from the table above was not diffed.

## A2. Ark Pixel Font and TakWolf's other projects: what else is on offer?

### Takeaway
Ark Pixel now builds only 10 and 12 px; its 16 px size was deprecated and removed in autumn 2026 (last build 2026.09.01), with TakWolf himself pointing users to GNU Unifont for 16 px. The only new pan-CJK TakWolf design is Jelly Pixel Font (果冻像素字体, round style, 12 px, started January 2026), which is a proof of concept with about 400 hanzi. No TakWolf project offers a usable pan-CJK font above 12 px.

### Cited Findings
- Ark Pixel latest release `2026.11.10`, published 2026-11-09T20:09:56Z; 5,022 stars; assets only for 10px and 12px, monospaced and proportional, in bdf/pcf/otb/dfont/ms.bitmap.ttf/otf/ttf/woff/woff2. — [GitHub API](https://api.github.com/repos/TakWolf/ark-pixel-font/releases/latest)
- README warnings: "the font is under active development and still lacks a large number of characters; for 10px/12px consider the transitional Fusion Pixel Font"; and "the 16px size is deprecated; related builds and assets have been removed ... the last build containing 16px is 2026.09.01 ... for a 16px substitute consider Unifont". — [ark-pixel-font README](https://github.com/TakWolf/ark-pixel-font/blob/master/README.md)
- Reasons given for dropping 16 px: it "actually contained only a small number of hanzi", "never reached a practical standard" as a pan-CJK set and had no Fusion-like stopgap; the Latin design "did not meet our expectations". Restart is "not yet determined"; 10 and 12 px come first. The glyph assets are archived under the original license. — [ark-pixel-font-16px-glyphs-archive README](https://github.com/pixel-font-studio/ark-pixel-font-16px-glyphs-archive/blob/master/README.md)
- Ark license: font OFL 1.1 (header "Copyright (c) 2021, TakWolf", no Reserved Font Name clause), build program MIT. — [LICENSE-OFL](https://github.com/TakWolf/ark-pixel-font/blob/master/LICENSE-OFL)
- Ark 12 px proportional coverage: 26,181 characters; CJK Unified 18,715 / 20,992; Ext A 1,777; Ext B 1,458; kana complete; GB2312 total 7,053/7,445 (level 1 3,641/3,755); Big5 total 12,006/13,461; Shift-JIS 6,465/7,037; KS X 1001 5,319/8,226. The Unicode table has no Hangul Syllables row. — [info-12px-proportional](https://github.com/TakWolf/ark-pixel-font/blob/master/docs/info-12px-proportional.md)
- Ark 10 px proportional coverage: 4,610 characters; CJK Unified 1,085 / 20,992; GB2312 1,378/7,445; Shift-JIS 1,287/7,037. — [info-10px-proportional](https://github.com/TakWolf/ark-pixel-font/blob/master/docs/info-10px-proportional.md)
- Ark language-specific versions are the same seven as Fusion (latin, zh-Hans, zh-Hant, zh-HK, zh-TW, ja, ko), with the same reference standards. — [ark-pixel-font README](https://github.com/TakWolf/ark-pixel-font/blob/master/README.md)
- Jelly Pixel Font 果冻像素字体: "open-source pan-Latin and pan-CJK pixel font, round (圆体) style"; repo created 2026-01-11; release `2026.11.10` (2026-11-09); 12 px only, monospaced + proportional; README warning: "currently only a proof of concept, unfinished, no usable instances yet". OFL 1.1 (Copyright 2026 TakWolf, no RFN) + MIT build. — [jelly-pixel-font README](https://github.com/TakWolf/jelly-pixel-font/blob/master/README.md)
- Jelly 12 px proportional coverage: 4,150 characters; CJK Unified 394 / 20,992; kana complete; GB2312 979/7,445; Shift-JIS 949/7,037. — [info-12px-proportional](https://github.com/TakWolf/jelly-pixel-font/blob/master/docs/info-12px-proportional.md)
- Retro Pixel Font 复古像素字体 is NOT CJK: "a set of open-source pixel fonts with a nostalgic game feel, mainly English, digits and symbols". Faces: Arcade (8 px), Cute Mono and Cute Prop (11 px), Petty 5H and Petty 5x5 (5 px), Thick (16 px). OFL 1.1 (no RFN). Latest release 2026.09.18. — [retro-pixel-font README](https://github.com/TakWolf/retro-pixel-font/blob/master/README.md)
- HZK Pixel Font 汉字库像素字体 (12 and 16 px, UCDOS-era Chinese bitmap fonts) has moved to the `pixel-font-legacy` organization and opens with a warning: "this font is not public domain; consider carefully and bear the copyright risk yourself". The glyph data comes from aguegu/BitmapFont, "possibly from UCDOS or early WPS", and a commenter traced it to Hong Kong's Compufont. Only the build program is MIT. — [hzk-pixel-font README](https://github.com/pixel-font-legacy/hzk-pixel-font/blob/master/README.md)
- TakWolf's tooling (all active in November 2026): `pixel-font-builder` ("a library that helps create pixel style fonts", MIT), `pixel-font-knife` (bitmap, glyph asset, cmap and kerning tools), `pixel-font-source` (new), `bdffont-python`, `pcffont-python`, `dfont-python`, `sfdfont-python`, `kbitfont-python` (Bits'N'Picas `.kbits`/`.kbitx`), plus .NET ports `bdffont-dotnet`, `pcffont-dotnet`, `kbitfont-dotnet`. Several libraries were renamed with a `-python` suffix (the old `TakWolf/bdffont` and `TakWolf/pcffont` URLs now redirect). — [TakWolf repositories](https://github.com/TakWolf?tab=repositories)
- Other TakWolf font repos seen: `pixel-glyphs-hangul-syllables` ("AC00..D7AF; Hangul Syllables", pushed 2026-11-23), `chaos-pixel-font-{arabic,thai,devanagari,tifinagh}`, `cozette-rebuild`, `qrcode-pixel-font`, `aseprite-universal-pixel-theme`. — [TakWolf repositories](https://github.com/TakWolf?tab=repositories)
- A web search summary claimed Ark Pixel reserves the name "Ark Pixel"; the current LICENSE-OFL file contradicts this (no Reserved Font Name line). — [LICENSE-OFL](https://github.com/TakWolf/ark-pixel-font/blob/master/LICENSE-OFL); contradicted by [third-party index](https://awesome.ecosyste.ms/projects/github.com%2Ftakwolf%2Fark-pixel-font)

### Inferences
- Ark Pixel 12 px is nearly as complete as Fusion 12 px for hanzi (18,715 vs 19,546 URO) but has no Hangul syllables of its own, so shipping Ark in addition to Fusion adds no new look: Fusion 12 px IS Ark 12 px plus Cubic 11 and Galmuri.
- The `pixel-glyphs-hangul-syllables` repo suggests TakWolf is drawing native Hangul for Ark; if that lands, Fusion's Korean look may change in a later release (worth pinning the Fusion version the app converts).
- The last Ark build with 16 px (2026.09.01) is still OFL and downloadable, but by the author's own account it holds few hanzi, so it is only useful for kana + Latin at 16 px.
- Jelly Pixel is the candidate to watch for a "second style" at 12 px, but at about 394 hanzi it cannot be shipped as a CJK font today.
- HZK 12/16 px should be rejected on provenance, in line with the maintainer's own warning.

### Gaps
- No TakWolf project named "Mini Pixel Font 迷你像素字体" (7 px) or a Galmuri-derived build was found in the first 60 repos by push date; the unauthenticated GitHub API limit was exhausted before the second page and the two organizations (`pixel-font-studio`, `pixel-font-legacy`) could be listed.
- Ark 16 px character counts in the 2026.09.01 build were not read.
- TakWolf's own curated list of third-party pixel fonts (if one exists in a repo or blog post) was not located.

## A3. GNU Unifont and the older GPL / X11 bitmap families: are they usable?

### Takeaway
GNU Unifont (16 px, version 18.0.01 of 16 September 2026) is the only complete, actively maintained, clearly licensed pan-CJK bitmap font at 16 px; it is dual-licensed OFL 1.1 or GPLv2+ with the font embedding exception, and unifoundry states outright that it can be used with non-free software. It now has three CJK flavors: default (Wen Quan Yi derived, G-source Chinese), `unifont_jp` (Japanese forms) and, new in 2026, `unifont_t` (Taiwan T-source forms). WenQuanYi Bitmap Song and efont-unicode-bdf are stale and carry GPL or mixed licenses that make them poor fits.

### Cited Findings
- Current version 18.0.01, dated 16 September 2026; earlier 2026 releases 17.0.04 (13 March 2026) and a 17.x release on 28 June 2026; 2025 releases on 19 April, 31 May, 9 September, 18 October and 1 November. — [unifoundry.com Unifont page](https://unifoundry.com/unifont/index.html)
- Design: "dual-width monochrome font, with glyphs in a grid of 8 or 16 pixels" wide by 16 high; covers "every printable code point in the Unicode Basic Multilingual Plane", with Plane 1 and Plane 2/3 CJK ideographs in the "Upper" series. — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- Downloads for 18.0.01: OpenType `unifont-18.0.01.otf` (5 MB), `unifont_jp-18.0.01.otf` (5 MB), `unifont_t-18.0.01.otf` (5 MB), `unifont_upper-18.0.01.otf` (1 MB), `unifont_csur`; PCF and BDF (about 1 MB gzipped each) for default, `_jp` and `_t`. "BDF and PCF font formats only support Unicode Plane 0 code points". — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- TrueType is no longer produced by the default build since 15.1.01 (12 September 2023); OpenType took its place. — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- Japanese variant: the "JP" OpenType/TrueType fonts "provide coverage of all of Unicode Plane 0 (using Japanese variants of CJK ideographs) plus the upper Unicode plane glyphs necessary" for "complete JIS X 0213 coverage". — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- T-source variant: in 17.0.04 (13 March 2026) "Kusanagi_Sans and Kao Chen-tung (高振東) added a new set of over 28,000 Unicode Standard T-source Chinese glyphs that parallel the Wen Quan Yi Unicode G-source Chinese glyphs", available as `unifont_t` BDF, PCF and OpenType. — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- The default Plane 0 CJK range is referred to as "the Plane 0 Wen Quan Yi range, U+2F00..U+9FFF" (changelog for 15.1.02). — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- License: "As of Unifont version 13.0.04, the fonts are dual-licensed under the SIL Open Font License (OFL) version 1.1 and the GNU GPL 2+ with the GNU font embedding exception." — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- LICENSE.txt: "The license for the compiled fonts is covered by the SIL Open Font License version 1.1 and by the above GPL terms with the GNU font embedding exception"; everything except the fonts (the tools) is GPLv2+. — [unifoundry.com LICENSE.txt](https://unifoundry.com/LICENSE.txt)
- "A user has asked if GNU Unifont can be used with non-free software. The answer is yes. The GNU Font Embedding Exception and the SIL OFL allow for that... The main purpose of the licensing is to require derivative fonts that others create to be released to the public under the same licensing terms, not to prohibit the use of those fonts with certain software." — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- Ark Pixel's maintainer describes Unifont as "a mature solution" for 16 px, noting it is a 宋体 (Song/Mincho-like serif) style. — [ark 16px archive README](https://github.com/pixel-font-studio/ark-pixel-font-16px-glyphs-archive/blob/master/README.md)
- WenQuanYi Bitmap Song 文泉驿点阵宋体: covers hanzi needed for Simplified Chinese, Traditional Chinese, Japanese and Korean ("more than 27,842 hanzi, fully covering GB2312/Big5/GBK/GB18030"), plus English, Japanese, Korean and other symbols; "five common screen sizes (9pt-12pt), over 210,000 hanzi bitmaps". Stable 0.9.9, test 1.0.0-RC1; the page was last edited 2010-03-13. — [wenq.org BitmapSong](http://wenq.org/wqy2/index.cgi?BitmapSong)
- WenQuanYi license: copyright of the WenQuanYi Board of Trustees, FangQ and Firefly; "GNU General Public License v2 (with an added clause permitting document embedding)". The page states: "using this GPL font in non-GPL monolithic software is a violation of the GPL license", and that companies who want to include the font without opening their source should contact FangQ to negotiate a license. — [wenq.org BitmapSong](http://wenq.org/wqy2/index.cgi?BitmapSong)
- efont-unicode-bdf (/efont/ Electronic Font Open Laboratory): last release 0.4.2 on 2004-09-15. It is an assembly of bitmaps from various origins. The README lists per-file origins, for example: 12 px = Baekmuk `gulim12.bdf` (Copyright 1986-2000 Hwan Design Inc., own license), `K12` (Toshiyuki Imamura, public domain), Shinonome `shnmk12` (public domain), Markus Kuhn `6x12` (public domain); 14 px = Baekmuk `dotum14`, `johab14.hex` (/efont/), `K14` (public domain); the optional 10 px `naga10` is "freely usable, but restricted". — [efont README](http://openlab.ring.gr.jp/efont/unicode/README)
- /efont/'s own glyphs are under a 3-clause BSD-style font license ("Redistribution and use in source and binary forms, with or without modification, are permitted provided that ... retain the above copyright notice ..."). — [efont COPYRIGHT](http://openlab.ring.gr.jp/efont/unicode/COPYRIGHT)
- GNU intlfonts: latest tarball `intlfonts-1.4.2.tar.gz`, 2021-03-12 (12 MB). — [ftp.gnu.org/gnu/intlfonts](https://ftp.gnu.org/gnu/intlfonts/)

### Inferences
- For a 16 px tier, Unifont under its OFL option has the same obligations as Fusion Pixel (see B1), so the earlier "GPL" concern does not apply. The earlier rejection was aesthetic, and the style has not changed: a 16 px Song-style design. What has changed is that there are now three regional flavors (default/G-source, JP, T-source) that map onto the app's existing ja / zh-Hans / zh-Hant split. Korean Hangul is in Plane 0 of every flavor.
- WenQuanYi Bitmap Song is effectively closed to the app unless the app itself is GPL-compatible: the maintainers publicly read the GPL as covering a program that bundles the font. Note the oddity that Unifont's CJK glyphs derive from Wen Quan Yi yet Unifont as a whole is offered under OFL; the app should rely on Unifont's license grant, not on WQY's.
- efont-unicode-bdf is a 2004-era patchwork whose CJK parts are better taken from their origins (Shinonome, K12/K14, Baekmuk), each with its own license; those are single-script fonts for the other researchers.

### Gaps
- Unifont's exact glyph counts per flavor (the page text near "for a total of about 59,000 glyphs" was only partially captured) were not confirmed.
- WenQuanYi Bitmap Song's exact pixel sizes (commonly given as 11, 12, 13, 15 and 16 px) and whether it contains all 11,172 Hangul syllables were not verified from the primary page; the page only says "9pt-12pt" and "Korean ... symbols".
- "wqy-unibit" (WenQuanYi Unibit 16 px, GPL) was not checked.
- GNU intlfonts' README (per-file CJK licenses, 16/24 px sets) could not be fetched (404 on the guessed path); its content is unverified.
- Baekmuk, Kochi and Arphic bitmap sets, X11 misc-fixed CJK (k14, jiskan16/24, hanglm16/24, gb16/24): not checked this session.

## A4. Other multi-script candidates and the curated collections: what did the sweep find?

### Takeaway
Outside TakWolf and Unifont, the only multi-script pixel fonts with real CJK coverage that turned up are LanaPixel (eishiya) and Silver (Poppy Works), both CC BY 4.0 on their face; Silver adds a non-CC "contact us above $100,000" condition on its page. The Western bitmap-font collections (Tecate/bitmap-fonts, int10h's Oldschool PC Font Pack) hold essentially no CJK. No new open pan-CJK pixel font at 14, 16 or 24 px was found.

### Cited Findings
- Silver (Poppy Works): the itch.io page states "Attribution 4.0 International (CC BY 4.0)" and "This font is free* for personal and commercial use", with the asterisk tied to: "if the budget of your production exceeds $100,000 USD in total spend or earnings" the user is asked to contact the studio to license the font. Single file `Silver.ttf` (3.5 MB). Supported languages listed include Japanese, Korean, Chinese (Simplified and Traditional). Released 2019-06-01, status "In development"; the most recent development log is "CJK Update 14", 2024-05-20. The page gives no native pixel size and no glyph counts. — [poppyworks.itch.io/silver](https://poppyworks.itch.io/silver)
- Silver users have reported missing Hangul, kanji and Traditional Chinese characters in the community board. — [itch.io thread](https://itch.io/t/468139/missing-glyphs-hangulkanjichinese-characters)
- LanaPixel (eishiya): the OpenGameArt page lists CC-BY 4.0, and (per search-engine summary of that page and of the author's Reddit post) the zip includes both OFL and CC-BY texts so users may choose either. A commenter noted that the bundled license file seemed to conflict with CC-BY; no resolution was visible. — [OpenGameArt](https://opengameart.org/content/lanapixel-localization-friendly-pixel-font); [Reddit mirror of author's post](https://redlib.ssps.io/r/gamedev/comments/h03ls4/heres_my_free_pixel_font_with_east_asian_language)
- LanaPixel size and coverage per a Chinese font-listing site: about 19,400 characters; a "NoKorean" build drops this from about 19k to about 8k glyphs; the "Everything" TTF is 3,081 KiB and the bitmap-only TTF 585 KiB; described as good for Japanese and Simplified Chinese with some Traditional Chinese support. — [100font.com](https://www.100font.com/thread-461.htm)
- Tecate/bitmap-fonts ("Monospaced bitmap fonts for X11, good for terminal use", last pushed 2022-01-20, 1,823 stars): the README's font list is Latin terminal fonts (artwiz, cherry, Dina, gohufont, Lemon, proggy, scientifica, spleen, tamsyn/tamzen, tewi, unscii, UW ttyp0, etc.). The only entry with CJK relevance is "M+ fonts" (M+ bitmap fonts, Japanese). No Unifont, WenQuanYi, efont, Baekmuk or other CJK set appears in the list. — [Tecate/bitmap-fonts README](https://github.com/Tecate/bitmap-fonts/blob/master/README.md)
- int10h.org Ultimate Oldschool PC Font Pack: the readme explains that some fonts are "remapped, since they're based on e.g. Japanese fonts, and the originals only had the lower (ASCII) half of the codepage present", flagged by "re." in the font name (for example "DOS/V re. PRC16 / 19"). — [int10h.org readme](https://int10h.org/oldschool-pc-fonts/readme/)
- The same author's font notes say "full CJK fonts are outside the scope of this collection; the version here is a custom remapping to CP437". — [viler-int10h/vga-text-mode-fonts FONTS.TXT](https://www.github.com/viler-int10h/vga-text-mode-fonts/blob/master/FONTS.TXT)
- Galmuri (quiple; Korean-first but multi-script, and a Fusion upstream): faces Galmuri14 (15 px), Galmuri11 (12 px), Galmuri11 Bold and Condensed (12 px), Galmuri9 (10 px), Galmuri7 (8 px); OFL. The README states that everything is the author's own creation EXCEPT "Latin-1, Kana, Kanji, some symbols and 2,355 Hangul syllables" in Galmuri14/11/9 (and except Latin-1, kana, kanji and some symbols in Galmuri7), and argues that in the US and Korea font files and code are copyrightable while typeface designs and, generally, bitmap fonts are not. — [quiple/galmuri README](https://github.com/quiple/galmuri/blob/main/README.md)
- Kreative's Bits'N'Picas ("Bitmap & Emoji Font Creation & Conversion Tools") is current: v2.2.2 released 2026-09-17. — [kreativekorp/bitsnpicas](https://github.com/kreativekorp/bitsnpicas)

### Inferences
- Galmuri's README is in effect a provenance disclosure: its kana, kanji and the KS X 1001 2,350-class Hangul are derived from pre-existing bitmap sources (the Korean-only researcher should pin down which). Since Fusion Pixel takes its Korean glyphs from Galmuri, this provenance is already inside what the app ships; it is OFL on its face, and the author relies on the "bitmap glyph shapes are not copyrightable" position for the non-original parts.
- Silver's "$100,000" sentence does not bind a CC BY licensee as a matter of the CC license text (CC BY 4.0 allows commercial use without a cap), but it signals the author's wishes; for a free app it is moot. The bigger practical issues are that Silver is a single TTF whose native size is undocumented on the page and that it must be checked for on-grid outlines before conversion.
- LanaPixel's glyph arithmetic (19.4k total, about 8k without Korean) implies full 11,172 Hangul plus roughly 6-7k hanzi/kana/other: a GB2312- or Jōyō-class set, not a full pan-CJK set, and with unified (not per-language) hanzi forms.
- Neither Silver nor LanaPixel distinguishes ja / zh-Hans / zh-Hant / ko glyph forms; that feature appears unique to the TakWolf fonts and Unifont's three flavors.

### Gaps
- LanaPixel's primary pages returned HTTP 403 to automated fetches: native size (reported elsewhere as 11 px), exact per-script counts, formats, the exact license files in the zip and the last update date remain unverified from the primary source.
- Silver's native pixel size and its Unicode block list (in a sticky itch.io thread) were not read; whether its outlines are on-grid is untested.
- int10h's license (widely cited as CC BY-SA 4.0) was not re-read this session, and whether any DBCS glyphs survive in the "DOS/V" faces was not confirmed beyond the two statements above (which indicate they do not).
- Not checked this session, so no claims made: Cozette, Spleen, Terminus, Tamzen, Pixel Operator, Monogram extended, Departure Mono (all believed Latin-only, unverified), Sarasa bitmap builds, Noto Sans CJK / Source Han Sans (believed to carry no embedded bitmap strikes, unverified), BabelStone fonts, Kreative fonts' CJK coverage, M+ bitmap, "awesome-pixel-fonts"-style lists, GitHub topic pages, itch.io CJK font collections, tiny 4x4-7x7 CJK experiments. Zpix and proprietary system strikes (SimSun, MS Gothic, Gulim/Batang) were not researched; they are proprietary and out of scope by the brief.
- A targeted web search for any open pan-CJK pixel font at 16 px or above, other than Unifont, returned only TakWolf projects.

## B1. SIL OFL 1.1: is converting to a custom bitmap format and bundling in an app allowed, and with what obligations?

### Takeaway
Yes. The OFL FAQ treats format conversion and subsetting as making a Modified Version, which is permitted; the converted font data stays under the OFL (nothing else in the app does), it must carry the copyright notice and license text, must not use any Reserved Font Name (none declared for Fusion/Ark/Jelly/Retro), must not be sold by itself, and artwork made with it is unrestricted.

### Cited Findings
- FAQ 2.2: "A change in font format normally is considered modification, and Reserved Font Names (RFNs) cannot be used." FAQ 2.2.1 carves out WOFF only "if the original font data remains unchanged except for WOFF compression"; FAQ 2.3 says other formats "alter the original font data more than WOFF"; FAQ 2.6 treats subsetting as modification. The FAQ does not address bitmap conversion specifically. — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 1.4: bundling with software is allowed "with both the Original Version and a Modified Version of the fonts"; the examples include "games and entertainment software, mobile device applications". — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 1.3: "Only the portions based on the Font Software are required to be released under the OFL." — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 1.20 (apps that bundle fonts): "At a minimum you must include the copyright statement, the license notice and the license text"; "A mention of this information in your About box or Changelog, with a link to where the font package is from, is good practice." FAQ 1.7: include "any copyright notices and licensing information as available in OFL.txt". — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 1.5 / 1.6 / 3.3: the font cannot be "sold by itself"; "The intent is to keep people from making money by simply redistributing the fonts"; it may be included in a larger software package, even one that is sold. — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 1.13: "Referencing or embedding an OFL font in any document does not change the license of the document itself." FAQ 1.1.1 (graphics made with the font): "No. You remain the author and copyright holder of that newly derived graphic or object." — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 5.3: with RFNs "you cannot use the Reserved Font Names in any way to identify the font to the user" in a Modified Version; FAQ 5.6 / 5.7: RFNs are optional, and under OFL 1.1 no names are reserved by default. — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- FAQ 1.17 / 1.21: if a user can extract the font from a product, they keep the right to "use, study, modify and redistribute it under the OFL"; the bundler "cannot legally prevent them from doing that". — [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- The four TakWolf fonts' LICENSE-OFL files contain no "with Reserved Font Name" clause (checked by text search of each file). — [fusion LICENSE-OFL](https://github.com/TakWolf/fusion-pixel-font/blob/master/LICENSE-OFL); [ark LICENSE-OFL](https://github.com/TakWolf/ark-pixel-font/blob/master/LICENSE-OFL)

### Inferences
- The app's converted bitmap files are Modified Versions: they must stay under OFL 1.1 in the public repo (a LICENSE/OFL file next to the converted data with the upstream copyright lines), and the app should show copyright + license text in an About/licenses screen. The app's own code and license are unaffected (FAQ 1.3).
- Where an upstream DOES declare a Reserved Font Name (common in Japanese and Korean OFL fonts), the converted font must be shown to users under a different name. For no-RFN fonts the original name may be kept, though the OFL also forbids using copyright holders' names to promote the Modified Version without permission (license condition 4, in the OFL text included in each LICENSE-OFL file).
- A free app plainly satisfies "not sold by itself"; so would a paid app.
- Users' published artwork is unencumbered (FAQ 1.1.1, 1.13).

### Gaps
- Fusion Pixel aggregates upstream fonts; whether any upstream (Cubic 11, BoutiqueBitmap, MisekiBitmap, Galmuri) declares an RFN that would matter when shipping that upstream directly was not checked (single-script researchers should check each OFL header).

## B2. GPL with the font embedding exception: does it cover bundling font data in an app?

### Takeaway
On its wording the GNU font exception covers only embedding the font in a "document"; it says nothing about linking or bundling font data into a program, and WenQuanYi's maintainers explicitly say bundling in non-GPL software violates the GPL. Unifont avoids the question twice over: it is also offered under OFL 1.1, and unifoundry states it may be used with non-free software.

### Cited Findings
- FSF exception text: "As a special exception, if you create a document which uses this font, and embed this font or unaltered portions of this font into the document, this font does not by itself cause the resulting document to be covered by the GNU General Public License. This exception does not however invalidate any other reasons why the document might be covered by the GNU General Public License. If you modify this font, you may extend this exception to your version of the font, but you are not obligated to do so." The FSF calls the exception "experimental but approved for general use". — [GNU GPL FAQ, FontException](https://www.gnu.org/licenses/gpl-faq.html#FontException)
- Unifont uses that exception verbatim and adds the OFL as an alternative for the compiled fonts. — [unifoundry.com LICENSE.txt](https://unifoundry.com/LICENSE.txt)
- Unifont's maintainers: use with non-free software is allowed; "The GNU Font Embedding Exception and the SIL OFL allow for that"; the purpose "is to require derivative fonts that others create to be released to the public under the same licensing terms". — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- WenQuanYi: "using this GPL font in non-GPL monolithic software is a violation of the GPL license"; enterprise users who do not want to open their source are told to negotiate a separate license. — [wenq.org BitmapSong](http://wenq.org/wqy2/index.cgi?BitmapSong)

### Inferences
- "Unaltered portions of this font" in the exception also sits awkwardly with format conversion: a converted bitmap table is arguably a modified font, which the exception does not cover even for documents. For any GPL+FE-only font the conservative reading is: converted data must be GPL, and whether an app that loads it becomes GPL-bound is contested (font-as-data vs. combined work). The two rights holders above read it in opposite directions for their own fonts.
- For Unifont, electing the OFL makes the analysis identical to B1. The converted Unifont data would be an OFL Modified Version; the app should say it uses Unifont under the OFL.
- Users' artwork: a raster image with stamped glyphs is not a "document embedding the font"; no font program is conveyed, so neither GPL nor OFL reaches the artwork (the OFL says so explicitly; for GPL this is an inference).

### Gaps
- The FSF's "explanatory essay" linked from the FAQ entry was not read; no FSF statement specifically about fonts bundled in applications was found.

## B3. CC BY 4.0 and CC BY-SA 4.0 fonts: what are the obligations?

### Takeaway
CC BY 4.0 permits conversion and redistribution provided attribution, a license link and an indication of changes are given; CC BY-SA 4.0 additionally forces the converted font data (an adaptation) to stay BY-SA, but not the app around it nor, in the researcher's reading, users' artwork. Creative Commons itself says its licenses are not recommended for software, and it publishes no font-specific guidance that was found, so the "is stamped text an adaptation?" question has no official answer.

### Cited Findings
- CC FAQ: "CC licenses may be applied to any type of work ... The only categories of works for which CC does not recommend its licenses are computer software and hardware." — [Creative Commons FAQ](https://creativecommons.org/faq/)
- CC FAQ license elements: "ShareAlike (SA), which requires adaptations of the material be released under the same license". The FAQ has separate entries "When is my use considered an adaptation?" and "If I create a collection that includes a work offered under a CC license, which license(s) may I choose for the collection?" — [Creative Commons FAQ](https://creativecommons.org/faq/)
- Silver's page pairs "CC BY 4.0" with a request to contact the studio if a production's budget or earnings exceed $100,000 USD. — [poppyworks.itch.io/silver](https://poppyworks.itch.io/silver)

### Inferences
- CC BY 4.0 attribution (license section 3(a)) requires: creator identification, copyright notice, license notice/URI, and an indication if the material was modified. For a converted font this means a credits entry such as "LanaPixel by eishiya, CC BY 4.0, converted to bitmap format" in the app and next to the data in the repo.
- CC BY-SA 4.0: the converted bitmap file is Adapted Material and must be BY-SA 4.0 (or a BY-SA compatible license). The app that merely ships it alongside other assets is a collection, not an adaptation, so the app's license is unaffected. This matters for int10h-style packs.
- Artwork: an image containing rasterized glyphs arguably reproduces the glyph shapes. Under BY that would at most call for attribution; under BY-SA a strict reading could make the artwork an adaptation subject to share-alike. Because bitmap glyph shapes are widely held non-copyrightable (see B5), many treat such output as free, but this is unsettled and a BY-SA font is therefore a worse fit for a tool whose users publish output than an OFL font, whose FAQ answers the question explicitly.
- Additional restrictions stated next to a CC license (Silver's budget threshold) are in tension with CC 4.0's own terms; treat them as the licensor's stated wish and note them.

### Gaps
- The CC BY 4.0 / BY-SA 4.0 legal code sections (3(a), 3(b), definitions of Adapted Material) were cited from the researcher's knowledge of the license text, not re-fetched this session; verify at https://creativecommons.org/licenses/by/4.0/legalcode before relying on the paraphrase.
- No Creative Commons FAQ entry addressing fonts specifically was found.

## B4. Regional "free font" terms (Japan, Korea, China) and named licenses: what typically blocks conversion + public-repo redistribution?

### Takeaway
This question was not researched from primary sources in this session (budget went to the catalog and the open licenses); only the WenQuanYi, efont/naga10 and HZK examples were verified. The pattern to check for each single-script font is whether BOTH modification (改変 / 수정 / 修改) AND redistribution of the modified file (再配布 / 재배포 / 二次分发) are granted; "free for commercial use" alone grants neither.

### Cited Findings
- Example of a "free but restricted" Japanese bitmap font inside an otherwise free collection: efont lists naga10 as "License: Freely usable, but restricted. See README.naga10 for detail (Japanese)" and ships it only as optional. — [efont README](http://openlab.ring.gr.jp/efont/unicode/README)
- Example of public-domain declarations for Japanese bitmap fonts: efont lists Shinonome 0.9.6 and K12/K14 (Toshiyuki Imamura) as "License: Public Domain". — [efont README](http://openlab.ring.gr.jp/efont/unicode/README)
- Example of a Korean vendor-copyright bitmap set with its own license file: Baekmuk gulim12/dotum14, "(c) Copyright 1986-2000, Hwan Design Inc. License: see 'README.baekmuk'". — [efont README](http://openlab.ring.gr.jp/efont/unicode/README)
- Example of a Chinese legacy bitmap font with no license at all: HZK (UCDOS) 12/16 px, flagged by its own repackager as "not public domain ... bear the copyright risk yourself". — [hzk-pixel-font README](https://github.com/pixel-font-legacy/hzk-pixel-font/blob/master/README.md)
- Fusion Pixel classifies Misaki's terms as an "untyped license, compatible with OFL-1.1" and redistributes its glyphs under the OFL. — [fusion-pixel-font README](https://github.com/TakWolf/fusion-pixel-font/blob/master/README.md)

### Inferences
- A checklist for the single-script researchers' candidates: (1) is modification allowed, (2) is redistribution of the modified/converted file allowed, (3) is redistribution allowed outside the original archive (many Japanese terms require the unmodified zip), (4) is embedding in apps allowed, (5) is there a name restriction (RFN or "rename if modified", as in the IPA Font License), (6) is a public repo "redistribution of the font by itself"? Korean foundry terms that say commercial use is allowed but modification/redistribution is prohibited fail (1)-(2); Chinese "免费商用" announcements usually license use, not repackaging, and fail (2) unless the font is also OFL.

### Gaps
- Not verified this session (do not cite without checking): the M+ FONTS LICENSE wording (believed to grant unlimited use, copying and distribution with or without modification, commercially or not); the IPA Font License v1.0 derivative-work conditions (believed to require renaming and a way to restore the original); typical フリーフォント clauses (商用利用可・改変可・再配布可); typical Korean 상업적 이용 가능 / 수정·재배포 금지 clauses; typical Chinese 免费商用 terms. The Japanese-only, Korean-only and Chinese-only researchers should quote these from each font's own terms.
- README.baekmuk and README.naga10 were not read.

## B5. Legal status of bitmap glyph shapes (US, Japan, China, Korea)

### Takeaway
In the US, typeface designs "as typeface" are excluded from copyright by regulation and the Copyright Office has treated bitmap fonts as mere depictions of typefaces, while font programs may be protected. Japan's Supreme Court (2000) and Korea's Supreme Court (1996) both refused copyright in ordinary typeface designs, though Korea protects font files as programs and typeface designs under design law since 2005. China's leading case (Founder v. P&G, final 2011) ended on implied license without deciding whether single glyphs are works. Not legal advice; licenses should be honored regardless.

### Cited Findings
- US: 37 C.F.R. 202.1(e) lists "typeface as typeface" among material not subject to copyright; a 1992 Copyright Office notice (final regulation) addresses registration of computer programs that generate typefaces. — [Copyright Office notice ML-443](https://law.resource.org/pub/us/compendium/ibr/ML-443.pdf)
- US: the Compendium of U.S. Copyright Office Practices, Chapter 900, has a section 906.4 titled "Typeface, Typefont, Lettering, Calligraphy, and Typographic Ornamentation". — [Compendium ch. 900](https://www.copyright.gov/comp3/chap900/ch900-visual-art.pdf)
- US (secondary source): the Office's 1988 policy decision (53 FR 38110) treated a bitmapped font as only a computerized depiction of a typeface and therefore not copyrightable. — [comp.fonts FAQ mirror](https://www.dcs.ed.ac.uk/home/latex/cff/cf_13.htm)
- US (interested party): Monotype reports that since 1992 the Office accepted registrations of font software with sufficient original authorship and that the Office has more recently been refusing some such registrations. — [Monotype](https://www.monotype.com/resources/update-application-copyright-law-typeface-design-and-font-software)
- Japan: Supreme Court, First Petty Bench, 7 September 2000 (平成10(受)332, the "ゴナ" typeface case), on "the copyrightability of printing typefaces": the appeal was dismissed and the typeface held not to be a work. — [courts.go.jp](https://www.courts.go.jp/hanrei/54774/detail7/index.html)
- Japan: the test from that decision is commonly summarized as requiring both "originality in the sense of striking features compared with existing printing typefaces" and "aesthetic qualities such that the typeface itself can be an object of artistic appreciation". — [JPO training text on typeface protection](https://www.jpo.go.jp/news/kokusai/developing/training/textbook/document/index/protection_of_type_face_2009_jp.pdf)
- China: Founder (北大方正) v. Procter & Gamble over the two characters "飘柔" in Founder's 倩体: on 5 July 2011 the Beijing No. 1 Intermediate People's Court dismissed Founder's claims in the final instance; the judgment did not state a clear position on whether the single characters were protected artworks and instead recognized P&G's use through "implied license". — [news report (China Business Journal via mydrivers)](https://news.mydrivers.com/1/200/200062.htm)
- Korea: Supreme Court decision of 23 August 1996, 94누5632, refused copyright registration for typeface designs (서체도안). — [Law Times commentary](https://www.lawtimes.co.kr/news/articleView.html?idxno=202418)
- Korea: later Supreme Court rulings (2001, cited as 98도732 and 99다50552) treated digital font files as computer programs protected by copyright; typeface designs have been protectable under the Design Protection Act since 2005. — [Korea Copyright Commission journal article](https://www.copyright.or.kr/eng/doc/quarterly_pdf/123%20A%20Study%20on%20the%20Typeface%20Design%20Protection%20in%20Korea.pdf)
- Korea/US (font author's statement, not a legal source): "at least in the US and Korea, font files and code are copyrightable but typeface designs are not, and likewise in both countries bitmap fonts are generally not copyrightable". — [quiple/galmuri README](https://github.com/quiple/galmuri/blob/main/README.md)

### Inferences
- The legal baseline in all four jurisdictions is that plain bitmap glyph shapes get weak or no copyright protection, which is why users' stamped artwork is low-risk under any of the licenses. The baseline does NOT make it safe to ignore license terms: contract terms, font-program copyright (Korea treats even font files as programs), design registrations (Korea, and China/Japan design or unfair-competition routes) and store takedown practices all still apply, and a public repository that redistributes font data is exactly the "font file" act that licenses regulate.
- Fonts of unclear provenance (HZK, ROM dumps, system strikes) should stay excluded on license grounds even where glyph-shape copyright is doubtful.

### Gaps
- The verbatim text of Compendium section 906.4 could not be extracted (the PDF was fetched but not parseable with the tools at hand); the section title and regulation are confirmed, the wording is not.
- The Chinese judgment text itself was not found; the summary relies on press coverage. Later Chinese cases (for example Hanyi's suits, where some courts recognized individual glyphs as artworks) were mentioned in the same coverage but not researched.
- The Korean case numbers come from secondary commentary; the judgments were not read on law.go.kr.

## B6. Technical: detecting lossless pixel fonts, formats, tools and storage cost

### Takeaway
The TakWolf fonts are the easy case: every release ships native BDF and PCF alongside on-grid TTF/OTF and bitmap-strike builds (OTB, "ms.bitmap.ttf"), so conversion can start from BDF with no outline analysis; Unifont likewise ships BDF/PCF. For TTF-only fonts (Silver, LanaPixel) an on-grid check with fontTools is needed. A full 1-bit CJK set is small: roughly 0.7 MiB uncompressed for Fusion's 38k glyphs at 12 px and about 2 MiB for all of Unifont's BMP at 16 px.

### Cited Findings
- TakWolf release formats per size and width mode: `bdf`, `pcf`, `otb` (OpenType bitmap), `dfont`, `ms.bitmap.ttf`, `otf`, `ttf`, `otf.woff`/`woff2`, `ttf.woff`/`woff2`. — [fusion-pixel-font releases](https://github.com/TakWolf/fusion-pixel-font/releases)
- Unifont formats: OpenType, PCF, BDF (Plane 0 only in BDF/PCF), plus specialized PSF; glyphs are authored in a simple text format ("This simple format has allowed many, many volunteers to contribute thousands of glyphs"). — [unifoundry.com](https://unifoundry.com/unifont/index.html)
- monobit (Rob Hagemans, MIT, pushed 2026-11-23): "the bitmap font multitool ... lets you modify and convert bitmap fonts. It supports dozens of bitmap font formats and a few vector font formats"; native text format `yaff`; Python 3.9+, `pip install monobit`; examples include `monobit-convert roman.bdf to --format=unifont` (BDF to Unifont HEX) and reading Windows `.fon`, PSF, raw binary and C-source fonts. — [monobit README](https://github.com/robhagemans/monobit/blob/master/README.md)
- Bits'N'Picas (Kreative Software): "Bitmap & Emoji Font Creation & Conversion Tools", v2.2.2 of 2026-09-17, Java. — [kreativekorp/bitsnpicas](https://github.com/kreativekorp/bitsnpicas)
- TakWolf's Python libraries: `pixel-font-builder` (builds OTF/TTF/BDF/PCF etc. from bitmaps), `bdffont-python` (BDF), `pcffont-python` (PCF), `dfont-python`, `kbitfont-python` (Bits'N'Picas formats). — [TakWolf repositories](https://github.com/TakWolf?tab=repositories)
- Fusion glyph counts used for the size estimates below: 28,410 (8 px), 25,918 (10 px), 38,213 (12 px), proportional builds. — [info-12px-proportional](https://github.com/TakWolf/fusion-pixel-font/blob/master/docs/info-12px-proportional.md)

### Inferences
- On-grid test for a TTF/OTF pixel font (researcher's method, standard fontTools usage): read `head.unitsPerEm` and the intended pixel size P; require `unitsPerEm % P == 0`; let `u = unitsPerEm / P`; for every glyph require all outline points to be on-curve (TrueType `glyf` flags; for CFF, only line segments), every coordinate to be a multiple of `u`, and every segment axis-aligned; also require advance widths and vertical metrics to be multiples of `u`. If all pass, rasterizing at exactly P px per em with no anti-aliasing and no hinting reproduces the source bitmap losslessly. Composite glyphs must be decomposed first; scaled or rotated components fail the test.
- Embedded bitmap strikes are a separate route: `EBLC`/`EBDT` (monochrome or gray strikes; this is what `.otb` and "ms.bitmap.ttf" files carry, and what system fonts such as SimSun or MS Gothic use), `CBLC`/`CBDT` (color PNG strikes) and `sbix` (Apple). For 1-bit work only EBLC/EBDT strikes with bitDepth 1 are relevant; fontTools can decompile them.
- BDF is the simplest lossless source (ASCII, one `STARTCHAR`/`BITMAP` block per glyph with `BBX` and `DWIDTH`); PCF is its compiled binary form; Unifont HEX is one line per code point (32 hex digits for 8x16, 64 for 16x16). Prefer BDF where upstream publishes it.
- Uncompressed 1-bit storage cost per square glyph: 8x8 = 8 bytes; 10x10 = 100 bits (13 bytes byte-padded); 12x12 = 18 bytes; 16x16 = 32 bytes; 24x24 = 72 bytes. Therefore:
  - GB2312 hanzi (6,763): 12 px about 119 KiB; 16 px about 211 KiB; 24 px about 476 KiB.
  - Hangul syllables (11,172): 12 px about 196 KiB; 16 px about 349 KiB; 24 px about 786 KiB.
  - CJK Unified Ideographs block (20,992): 12 px about 369 KiB; 16 px about 656 KiB; 24 px about 1.44 MiB.
  - Fusion 12 px (38,213 glyphs at 18 bytes): about 672 KiB; Fusion 8 px (28,410 at 8 bytes): about 222 KiB.
  - Unifont BMP upper bound (65,536 at 32 bytes): 2.0 MiB per flavor; three flavors differ only in the CJK range, so the JP and T flavors can be stored as deltas (the T set is "over 28,000" glyphs, about 0.9 MiB before compression).
  Add per-glyph metrics (advance, bbox) and a code-point index; general-purpose compression typically shrinks CJK bitmaps further (Unifont's whole BDF is about 1 MB gzipped per unifoundry).
- Language variants as deltas: Fusion's ja / zh-Hans / zh-Hant / ko builds share most glyphs; storing one base table plus per-language override tables avoids quadrupling the data.

### Gaps
- `otf2bdf` and FontForge were not checked for current status this session.
- No measurement was made of the app's actual compact format; the byte figures are arithmetic on glyph counts, not measured file sizes.
- The OpenType specification pages for EBLC/EBDT/CBDT/sbix were not fetched; table descriptions above are from the researcher's knowledge.
