# Japanese pixel (bitmap) fonts that could be bundled in a pixel-art editor (as of 2026-11-26)

Reading notes for the report writer:

- "Verified" means I read the primary page myself during this research (URL given). Anything taken from a search-result summary or a third-party article is marked "secondary" or "unverified".
- I did not download or open any font file. Statements about what is inside an archive (README text, exact glyph counts, whether outlines sit on the pixel grid) come from the distribution pages, not from inspecting files.
- Sizes are written width x height in pixels of the full-width (kanji) cell unless stated.
- JIS X 0208 has 6,355 kanji (level 1 = 2,965, level 2 = 3,390) plus 524 non-kanji. Where a page says only "JIS X 0208 対応" or "第一・第二水準", I report that wording and do not invent a glyph count.

## Key question 1: Which Japanese pixel fonts with kanji coverage have licenses that clearly permit bundling, format conversion, and redistribution of converted data in a public repo?

### Takeaway
There is a large, clearly usable pool: about 22 public-domain X11-era fonts at 12, 14, 16, 18, 20 and 24 px (Shinonome gothic/mincho/marumoji, K12/K14, jiskan16s, Izumi16, milkjf16, Kappa20, Ayu 18/20, Kaname-cho 12, k12x10), the M+ licensed family (M+ BITMAP 10/12, PixelMplus, Misaki, k8x12 family, k6x8, k12x8), and SIL OFL 1.1 fonts (KH Dot series at 12/16/24/32 px in mincho, bold mincho, rounded, textbook and clerical styles; DotGothic16; x8y12pxDenkiChip). The sizes and styles the app lacks today (14, 16, 18, 20, 24, 32 px; mincho, rounded, bold, kyokasho, reisho) are all available without any license ambiguity.

### Cited Findings

#### A. Public domain (per the distributor's license table)

The JF Dot ("自家製ドットフォント") page by 自家製フォント工房 is the single best index. It states that its fonts are bitmap fonts published as open source, public domain or freeware, re-built as outline TrueType "under usage terms that permit data format conversion", that the TTFs also contain embedded bitmaps, and that all fonts cover kanji up to JIS level 2, some up to level 4. The latest build noted on the page is 2015-05-28. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/) (the https certificate is invalid; the page loads over http)

The page's license table lists these as "パブリックドメイン" with: copyright waived by the creators; personal use, commercial use, embedding in apps / web font use, and modification / redistribution all "possible without restriction"; credit or license notice "not needed in any case"; no warranty. JF 工房 also states it holds no copyright and asserts no rights of its own over the converted outlines. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)

Fonts in that public-domain group (name as shipped, original author as credited on the page, stated coverage):

| Font | Size / style | Original author(s) per page | Stated coverage |
|---|---|---|---|
| JFドット東雲ゴシック12 / 14 / 16 | 12, 14, 16 px gothic (bold variant included) | The Electronic Font Open Laboratory | JIS X 0208:1983 |
| JFドット東雲明朝12 / 14 / 16 | 12, 14, 16 px mincho (bold included) | same | JIS X 0208:1983 |
| JFドット東雲まるもじ12 | 12 px "marumoji" rounded handwriting style (bold included) | same | JIS X 0208:1983 |
| JFドットK12 | 12 px (bold included) | 橘浩志 / 今村俊幸 | JIS X 0213:2000 |
| JFドットK14, K14-2004 | 14 px (bold included) | 橘浩志 / 今村俊幸 | JIS X 0213:2000 and :2004 |
| JFドットjiskan16s (-1990, -2000, plain) | 16 px; half-width part taken from Shinonome Gothic 16, "all characters public domain" | JEITA / 安岡孝一 / 今村俊幸 / 花高信哉 | JIS X 0208:1990, X 0213:2000, X 0213:2004 |
| JFドット出水ゴシック16 | 16 px gothic (bold included) | Yu=Izumi | JIS X 0213:2000 |
| JFドットmilkjf16 | 16 px (bold included) | 日本農園 / 山内千里 | JIS X 0208:1983 |
| JFドットAyuゴシック18, Ayu明朝18 | 18 px gothic and mincho | After X-TT Project | JIS X 0208:1990 |
| JFドットAyuゴシック20 | 20 px gothic | After X-TT Project | JIS X 0208:1990 |
| JFドットKappa20, Kappa20-0213 | 20 px, vertical writing supported (bold; the 0213 one is bold only) | 狩野宏樹 / 永尾制一 | JIS X 0208:1990; JIS X 0213:2000 |
| JFドット要町12 | 12 px | 中村隆生 | JIS X 0208:1983 |
| JFドットk12x10 | 12 x 10 px | ぞろよし | JIS X 0208:1990 |

— [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)

- Shinonome primary source: the /efont/ project took over maintenance of 古川泰之's original bitmap font; "ライセンスはすべて、Public Domain です" (all licenses are public domain). Styles listed: 12 px gothic, 12 px mincho, 12 px marumoji, 14 px gothic, 16 px gothic, 16 px mincho. Last release 0.9.11 on 2004-09-15. — [efont Shinonome](http://openlab.ring.gr.jp/efont/shinonome/)
- Conflict to note: the efont page lists no 14 px mincho, but the JF Dot package ships "JFドット東雲明朝14". Where that 14 px mincho comes from (a later CVS state or another source) is not explained on either page. — [efont Shinonome](http://openlab.ring.gr.jp/efont/shinonome/); [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- jiskan16 and jiskan24 with the original half-width glyphs are NOT fully public domain: the full-width part is public domain, but the half-width part is Sony's (12x24 and 8x16) and needs the copyright notice and license text (sony.txt in the archive) wherever the half-width data is redistributed in reusable form. The "jiskan16s" builds avoid this by using Shinonome half-width glyphs. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- jiskan24 (JEITA / 矢木達也) at 24 px: full-width part public domain, coverage JIS X 0213:2000 and :2004. "jiskan24h" swaps the half-width part for Hibiya 24 (平木敬太郎), which is SIL OFL 1.1, so license notice is required where that half-width data is redistributed in reusable form. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- GNU Unifont's Japanese build (unifont_jp, 16 px) uses the public-domain Izumi16 glyphs: "Unifont 12.1.03 replaced the Jiskan16 glyphs with the public domain Izumi16 glyphs", and gives "complete representation of the kanji in JIS X 0213". Current version 18.0.01, available as OTF, PCF and BDF; dual-licensed OFL 1.1 or GPL 2+ with font embedding exception since 13.0.04. — [unifoundry.com Unifont](https://unifoundry.com/unifont/index.html)

#### B. M+ FONTS LICENSE family (effectively unrestricted)

- M+ license text (as bundled in the PixelMplus repo, "Copyright (C) 2002-2013 M+ FONTS PROJECT"): "These fonts are free software. Unlimited permission is granted to use, copy, and distribute them, with or without modification, either commercially or noncommercially. THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY." — [PixelMplus LICENSE_E](https://raw.githubusercontent.com/itouhiro/PixelMplus/master/misc/mplus_bitmap_fonts/LICENSE_E)
- JF Dot's table for M+ FONT LICENSE fonts: copyright held by each creator; commercial use, app embedding / web font, modification / redistribution all unrestricted; no credit needed. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- M+ BITMAP FONTS (森下浩司), as re-built by JF Dot: JFドットM+10 and M+12 (monospace, bold included), M+H10, M+H12, M+S10 (proportional Latin, bold included), M+Q10 (proportional Latin); all JIS X 0208:1990. The page says these share their source with PixelMplus but lack PixelMplus's added symbols, add proportional Latin variants, and contain bitmaps. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- PixelMplus10 / PixelMplus12 (itouhiro): outlines of the 10 px and 12 px M+ bitmap fonts; all JIS level 1 and 2 kanji plus ISO-8859-1 and some extra symbols; TrueType outline with NO embedded bitmaps; has a bold; M+ FONT LICENSE. — [PixelMplus README](https://raw.githubusercontent.com/itouhiro/PixelMplus/master/README.md). The repository was last pushed 2022-02-22 and is not archived. — [GitHub API, itouhiro/PixelMplus](https://api.github.com/repos/itouhiro/PixelMplus)
- littlelimit.net fonts (門真なむ): k6x8 (6x8), Misaki (8x8), k8x12 (8x12), k12x8 (12x8). License on the family page, in both languages: "These fonts are free software. Unlimited permission is granted to use, copy, and distribute them, with or without modification, either commercially or noncommercially. THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY." / 「あらゆる改変の有無に関わらず、また商業的な利用であっても、自由にご利用、複製、再配布することができますが、全て無保証とさせていただきます。」 — [littlelimit.net font page](https://littlelimit.net/font.htm)
- Misaki (美咲フォント): 8x8 px; supports JIS level 1 and 2; all glyphs except some symbols fit in 7x7 so characters can be set solid. Three variants: 美咲ゴシック, 美咲明朝 (the gothic with the NON-kanji glyphs replaced by mincho-style shapes, so kanji are the same), 美咲ゴシック第2 (half-width 3x7 and kana filling 7x7). Formats: TTF, X11 BDF, PNG, PC-E500 FNT. Latest version 2021-05-05. The TTF no longer bundles embedded bitmaps (dropped 2015-04-10). — [littlelimit.net Misaki](https://littlelimit.net/misaki.htm)
- k8x12: 8x12 px, JIS level 1 and 2 plus some symbols; variants k8x12 (original), k8x12L (vertically elongated kana), k8x12S (non-kanji 8 px high with dakuten placed above, for the 8x8 limits of old consoles). Formats TTF (outline), PNG, X11 BDF. Latest 2021-05-05. — [littlelimit.net k8x12](https://littlelimit.net/k8x12.htm)
- k12x8: 12x8 px (wide, short); JIS level 1 and other symbols only; level 2 not implemented; described by the author as an unpolished alpha that may change. — [littlelimit.net k12x8](https://littlelimit.net/k12x8.htm)
- k6x8: 6x8 px, JIS level 1 and 2 plus some symbols; glyphs fit in 5x7. Also shipped as JFドットk6x8 under M+ FONTS LICENSE. — [littlelimit.net k6x8](https://littlelimit.net/k6x8.htm); [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- 5x5 ノスタルジア (5x5 Nostalgia): glyph body 5x5, cell 6x12 including spacing; main version has 2,398 characters in total and the "Alt" variant has no kanji; free on BOOTH (v1.00, updated 2023-01-14); license described as the same as the "(旧) M+ FONT LICENCE": embedding in games, web font use, modification and redistribution are all allowed ("煮るなり焼くなりご自由にどうぞ"). — [BOOTH 5x5 ノスタルジア](https://booth.pm/ja/items/4442315)
- ベストテン FONT (BestTen, FLOP DESIGN): 10x10 px; two cuts, ベストテンDOT (plain pixels) and ベストテンCRT (visually processed, so not a clean pixel design); hiragana, katakana and Latin are original, the rest is filled from PixelMplus10; about 7,200 glyphs; OpenType; free (0 yen) on BOOTH; "商用・非商用問わず使用可能", "プログラムへの埋め込みが可能です"; stated to be an M+ BITMAP FONTS derivative that "follows" the license "Copyright(c) 2021 M+ FONTS PROJECT". — [BOOTH ベストテンFONT](https://booth.pm/ja/items/2747965)

#### C. SIL Open Font License 1.1

- KH Dot font series (KHドットフォント): designed by 平木敬太郎 between 1991 and 1996, originally sold as the 『電脳フォント』 series through the TAKERU software vending machines with paid commercial licenses, now released by the designer's goodwill under SIL OFL 1.1 via 自家製フォント工房. 15 typefaces at 12 to 32 px; every font includes all kanji up to JIS level 2; monospace outline TTF with embedded bitmaps; build 2015-05-27 (khdotfont-20150527). Glyph copyright stays with 平木敬太郎. — [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/)
- KH Dot typeface list as given on the page: 小伝馬町12 / 幾何学的カナ / 小かな (square gothic); 神楽坂12 (mincho); 道玄坂12 (bold mincho); 小伝馬町16 / 幾何学的カナ (square gothic); 秋葉原16 (rounded gothic); 神楽坂16 (mincho); 道玄坂16 (bold mincho); 人形町16 (kyokasho, textbook style); 八丁堀16 (reisho, clerical script); 兜町16 (fantail); 日比谷24 (mincho); 日比谷32 (mincho). — [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/)
- A 2015 Impress review of the same package lists the sizes as 12, 16, 24 and 36 dots, which conflicts with the distributor's "12 to 32" and "日比谷32". The distributor's page is the primary source. — [Impress Forest review](https://forest.watch.impress.co.jp/docs/review/704764.html); contradicted by [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/)
- DotGothic16 (Fontworks, on Google Fonts): adapted from an older 16x16 gothic bitmap typeface; covers all glyphs in Adobe-Japan1-3 plus GF Latin Core; SIL OFL. — [DotGothic16 README](https://raw.githubusercontent.com/fontworks-fonts/DotGothic16/master/README.md). Repository last pushed 2022-10-06. — [GitHub API, fontworks-fonts/DotGothic16](https://api.github.com/repos/fontworks-fonts/DotGothic16)
- x8y12pxDenkiChip (でんきチップ, hicc / 患者長ひっく): compact bold pixel font built on 2 px strokes, 12 px tall; Latin proportional, digits 6 px advance, kana 8 px, kanji 10 px; JIS level 1 kanji, 2,965 characters, added in v1.100 on 2026-11-01 (first release v1.000 on 2026-02-19); vertical writing supported; TTF with an embedded 12 px bitmap strike, plus a no-bitmap TTF in the repo; SIL OFL 1.1 with NO Reserved Font Name declared (the author asks only that a modified font published on its own not be named confusingly). The README warns many kanji are simplified shapes and unsuitable where exact strokes matter. — [DenkiChip README](https://raw.githubusercontent.com/hicchicc/x8y12pxDenkiChip/main/README.md)
- The author's site summary of the OFL editions: commercial use OK; embedding in software OK "with OFL.txt stated or bundled"; modification and redistribution OK under OFL; no standalone sale; no RFN. DenkiChip, x5y8pxNegaTape and x5y8pxNegaClip are the OFL-edition fonts so far. — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- LanaPixel (eishiya): designed for 11 px; dual-licensed OFL or CC BY 4.0 at the user's choice; the author's own page says many CJK characters are supported but "many of them are nearly illegible due to the small size". — secondary, from search summaries of [OpenGameArt LanaPixel](https://opengameart.org/node/114657)

#### D. Custom but permissive license

- hicc "original license" fonts (everything on the site other than the three OFL ones): "フォントから生成されるデータは全て無償で利用できます" (all data generated from the fonts may be used free); shipping the .ttf with games and commercial use allowed; "加工・改変・再配布も可能となっていますが、フォントの著作権は放棄しておりません" (processing, modification and redistribution allowed, copyright not waived); nobody may claim authorship; selling the font itself or similar acts prohibited; credit optional; terms may change without notice but will never start charging. — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- The same site announces that OFL editions of the remaining fonts will be released one by one, that future updates and fixes will in principle go only to the OFL editions, and that official distribution of the custom-license editions is expected to end. — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- hicc original-license fonts and latest versions: x14y24pxHeadUpDaisy (2025-09-19, bitmap embedded), x12y16pxMaruMonica (2025-09-03), x10y12pxDonguriDuel (2025-01-10), x12y12pxMaruMinyaM (2024-01-19), x12y16pxSolidLinker (2023-10-29), x12y12pxMaruMinya (2023-07-14), x12y16pxLineLinker (2020-02-23), x16y32pxGridGazer (2019-06-26), x12y20pxScanLine (2018-12-27), x14y20pxScoreDozer (2018-10-25), x8y12pxTheStrongGamer (2018-05-11). — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- MaruMinya kanji coverage: all 2,965 JIS level 1 kanji and nearly all of the 3,390 level 2 kanji. — secondary, from a search summary of [Impress Forest review, Nov 2023](https://forest.watch.impress.co.jp/docs/review/1546728.html)
- MaruMonica's 2025-09-03 update fixed 14 kanji including level 2 characters (妛, 廼, 瞎, 譫, 鷦 and others), which shows it carries level 2 kanji. — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- Silver (Poppy Works): CC BY 4.0, "free for personal and commercial use" with attribution to Poppy Works, BUT the page adds that productions whose budget "exceeds $100,000 USD in total spend or earnings" should contact them to license it. Credits name Itou Hiro (PixelMplus) as a major contributor. Japanese is listed among supported languages; CJK coverage is described as ongoing. — [Silver on itch.io](https://poppyworks.itch.io/silver)

### Inferences
- For a public repo that commits converted glyph data, the public-domain group and the M+ license group are the lowest-friction choices: neither requires attribution, license text, or name changes. OFL fonts need the license and copyright notice kept with the data, and converted data counts as a Modified Version, so any Reserved Font Name matters. DenkiChip declares none. Whether the KH Dot and DotGothic16 OFL headers declare an RFN was not checked.
- The JF Dot TTFs are a conversion of BDF originals. Because the app's pipeline accepts BDF, the original BDFs (efont Shinonome, the X11 distribution fonts for K14/jiskan, and so on) are the cleaner source; the JF Dot package is mainly useful as a license index and as a fallback with embedded bitmaps.
- hicc's custom license permits modification and redistribution in so many words, so converting and committing the data is covered. The one soft spot is that redistribution in a public repo sits next to a ban on "selling the font or similar acts"; a free app is not a sale. Waiting for the OFL editions would remove even that.
- BestTen's own page never states modification or redistribution rights; it relies on the M+ license for the borrowed kanji, but the original kana and Latin are FLOP DESIGN's. Treat redistribution of converted data as unconfirmed. Since its kanji are PixelMplus10's, it adds little beyond a different kana/Latin look at 10 px.
- Silver's CC BY 4.0 grant cannot legally be narrowed by a side note, but the revenue-threshold request makes it a poor fit for a clean-license catalog. Its native pixel size was not confirmed.

### Gaps
- Exact glyph counts for most fonts. Pages say "JIS X 0208", "第一・第二水準" or "JIS X 0213" without numbers; confirm by counting glyphs in the BDF files.
- Whether the outlines in the hicc, KH Dot, PixelMplus and BestTen-DOT TTFs lie exactly on the pixel grid. All are described as pixel fonts with a stated size, but no file was inspected.
- Original BDF download locations for K12/K14, Kappa20, Ayu, Izumi16, milkjf, Kaname-cho and k12x10. The JF Dot page links each author's site, but I did not follow those links, and several 2000-era hosts may be gone.
- The primary texts of the public-domain declarations inside each original archive. The "public domain" status here rests on the efont page (Shinonome) and on JF Dot's license table (all others).
- Whether KH Dot or DotGothic16 declare a Reserved Font Name; which older 16 px bitmap face DotGothic16 was adapted from (the README does not name it).
- LanaPixel's actual kanji count and its primary license text (the GitHub README URL I tried returned 404).
- Nosutaru-dot (M+), Enka Dot Gothic 24, Mona 12 Text JP appear in a third-party list tagged OFL; I found no primary source for any of them. — [fontmeme Japanese pixel fonts](https://fontmeme.com/jfont/japanese-pixel-fonts/)
- かたすみドット ほそじ/ふとじ x8y8 (BOOTH, "商用利用可", version 202602; modified redistributions must say they are modified): kanji coverage not confirmed. — secondary, [BOOTH かたすみドット](https://booth.pm/ja/items/7963135)
- Kiwi Soda / KiwiMaru-style pixel fonts, めもわーる, ニクキュウ, "k4x4" and other 4x4 kanji experiments: searches returned nothing relevant.

## Key question 2: What do the licenses actually say, and which are ambiguous or restrictive?

### Takeaway
Three tiers are clean (public domain, M+ license, OFL). Naga10, Elisa 8 and Pau16 are not usable commercially without permission from authors who can no longer be reached, and the Nu mochi fonts explicitly forbid both redistribution and distributing extracted glyph data, which rules out a public repo.

### Cited Findings
- ナガ10 (Naga10, 永尾制一): 10 px in three styles, JFドットナガ10 (gothic), ナガみん10 (mincho), ナガまる10 (rounded), JIS X 0208:1990, bold included. License: personal use allowed; commercial use "requires consulting the copyright holder", and the distributor notes the contact address has been dead for over 15 years; redistribution allowed if the archive is unchanged, or as a format conversion with the original README attached and a statement that the original terms apply. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- 恵梨沙フォント (Elisa, 恵梨沙フォントプロジェクト): 8 px, JIS X 0208:1990, glyphs fill the whole 8x8 cell so they touch when set solid (the distributor rates it as equivalent to a 9 px font). License: "原則として非商用の個人使用のみ"; commercial use requires consultation; modification / redistribution requires the creators' permission. JF Dot distributes it with formal permission. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- ぱうフォント (Pau16, 大野泰明): 16 px, JIS X 0208:1990; non-commercial only; redistribution requires contacting the author, who is unreachable. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- Nu きなこもち / あんこもち / よもぎもち (さゆぬ, v1.0.0, posted 2018-11-23, updated 2020-01-04): 8x8 tile, glyph body within 7x7, rounded retro-console look; kana shared across the three, Latin differs; only 612 kanji. Terms: images, video and documents may be made and published commercially without credit; "このフォント自体を再頒布（送信可能化）してはいけません" (no redistribution); a derived font may be made for private use but "それを頒布してはいけません", where "new font" explicitly includes "images cut out one character at a time" and any data usable like a font; embedding in an app is allowed only "to display fixed strings contained in the application" and only if the font data cannot technically be extracted. — [こかげ Nu mochi page](https://kokagem.sakura.ne.jp/font/mochi/)
- 横浜ドット: about 1,000 kanji; use (commercial or private) requires following the author's X account or reposting the release post. — secondary, from a search summary of [Impress Forest news](https://forest.watch.impress.co.jp/docs/news/1641883.html)
- 触手のしょほんと。: full-width glyphs within 7x7; personal and commercial use and embedding in games are free, but redistributing the unmodified font file on its own is prohibited; kanji coverage unknown. — secondary, from search summaries of [BOOTH item 3719889](https://booth.pm/ja/items/3719889)
- Zpix: "FREE for Education/Personal Product, pay for Commercial/Business Product"; 12 px (11 + 1 padding); 21,998 characters. — [laqieer/gba-free-fonts list](https://www.github.com/laqieer/gba-free-fonts/blob/main/others.md)
- Fusion Pixel's own README classifies Misaki as "No type license, compatible with OFL-1.1", which is an independent reading that the littlelimit terms are OFL-compatible. — [Fusion Pixel Font README](https://raw.githubusercontent.com/TakWolf/fusion-pixel-font/master/README.md)

### Inferences
- The Nu mochi terms fail on three separate points for this app: a user-typed Text tool is not "fixed strings", a public repo makes the data extractable, and committed converted glyphs are exactly the "data usable like a font" the terms forbid distributing.
- Naga10 is the only 10 px mincho and 10 px rounded design found, which makes its license status a real loss. Format conversion and redistribution are permitted with the README attached; it is the commercial-use clause that blocks it. Whether a free app with no ads or purchases counts as commercial use is a judgment the app owner would have to make, and the author cannot be asked.
- Elisa is blocked for the same reason, more strictly (modification also needs permission).

### Gaps
- The original README texts for Naga10 and Elisa were not read; the terms above are JF Dot's paraphrase. A search for the Elisa project's own page found nothing.
- 横浜ドット and 触手のしょほんと。 terms are from search summaries only.

## Key question 3: Which fonts offer a visibly different style from plain gothic?

### Takeaway
Mincho is available at 12, 14, 16, 18, 24 and 32 px, rounded at 12 and 16 px, bold at 12 px (DenkiChip, DonguriDuel) and 12/16 px (bold mincho 道玄坂), plus two styles with no equivalent elsewhere: textbook (人形町16) and clerical script (八丁堀16). Nothing clearly licensed was found at 7, 9 or 11 px.

### Cited Findings
- Mincho: 東雲明朝 12/14/16 (public domain), Ayu明朝18 (public domain), 神楽坂12 and 16, 道玄坂12 and 16 (bold mincho), 日比谷24 and 32 (OFL). — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/); [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/)
- Misaki Mincho is mincho only in its kana and other non-kanji glyphs; the kanji are the gothic ones. — [littlelimit.net Misaki](https://littlelimit.net/misaki.htm)
- Rounded: 東雲まるもじ12 (public domain); 秋葉原16 rounded gothic (OFL); x12y12pxMaruMinya (rounded gothic), x12y12pxMaruMinyaM (marumoji), x12y16pxMaruMonica (condensed rounded gothic) (hicc custom license). — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/); [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/); [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- Bold: x8y12pxDenkiChip (compact bold, OFL), x10y12pxDonguriDuel (bold, custom license); most JF Dot fonts also ship a generated bold variant. — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/); [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
- Other styles: 人形町16 (kyokasho), 八丁堀16 (reisho), 兜町16 (fantail), 小伝馬町 幾何学的カナ (geometric kana) at 12 and 16. — [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/)
- Retro-game and display styles from hicc: x8y12pxTheStrongGamer (retro game), x14y24pxHeadUpDaisy (HUD), x12y20pxScanLine (scanline), x16y32pxGridGazer (large, grid), x14y20pxScoreDozer (score display), SolidLinker / LineLinker (outline overlap). — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/)
- Retro-console constraint style: k8x12S places dakuten above 8 px-high kana, modeled on the 8x8 tile limits of old consoles. — [littlelimit.net k8x12](https://littlelimit.net/k8x12.htm)
- Unusual cell shapes: k12x8 (wide), k12x10, k6x8 (5x7 body), 5x5 ノスタルジア. — [littlelimit.net font page](https://littlelimit.net/font.htm); [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/); [BOOTH 5x5 ノスタルジア](https://booth.pm/ja/items/4442315)

### Inferences
- A shortlist that adds the most variety per font with no license doubt: 東雲明朝 12/14/16, 東雲まるもじ12, K14, Kappa20, Ayu明朝18, 日比谷24, 道玄坂16, 秋葉原16, 人形町16, 八丁堀16, k8x12, DenkiChip.
- The "bold" variants in JF Dot are probably mechanical double-strikes rather than drawn designs; that is a guess from the uniform "(太字あり)" labeling, not something the page says.

### Gaps
- Kanji coverage of the hicc fonts other than DenkiChip, MaruMinya and (partly) MaruMonica is not stated on the site. Several of the display fonts may be kana and Latin only.
- No handwritten kanji pixel font with a clear license was found. KFひま字 appeared in results but is described as a handwriting-style round font, not confirmed to be a pixel design.

## Key question 4: Overlap with Fusion Pixel Font, and the status of Ark Pixel 16 px

### Takeaway
Of all the Japanese candidates, only Misaki is a declared Fusion Pixel upstream (its 8 px Japanese kanji), so Misaki Gothic is redundant and nearly everything else is new. Ark Pixel's 16 px size has been deprecated and its builds removed; it is not a candidate.

### Cited Findings
- Fusion Pixel upstreams: 8 px uses Misaki ("提供 8 像素日语汉字字形"), MisekiBitmap (Simplified Chinese), BoutiqueBitmap7x7 (Traditional Chinese), Galmuri (Korean); 10 px uses Ark Pixel as base plus BoutiqueBitmap9x9 and Galmuri; 12 px uses Ark Pixel as base plus Cubic 11 and Galmuri. — [Fusion Pixel Font README](https://raw.githubusercontent.com/TakWolf/fusion-pixel-font/master/README.md)
- Ark Pixel Font offers 10 px and 12 px. The 16 px size is deprecated, its builds and assets removed; the last release containing 16 px was 2026.09.01. The README recommends Unifont as the 16 px replacement, gives no per-language glyph counts, and says the font is still missing many characters. License OFL 1.1. — [Ark Pixel Font README](https://raw.githubusercontent.com/TakWolf/ark-pixel-font/master/README.md)
- Both repos are active: Ark Pixel last pushed 2026-11-25, Fusion Pixel 2026-11-25. — [GitHub API, TakWolf/ark-pixel-font](https://api.github.com/repos/TakWolf/ark-pixel-font); [GitHub API, TakWolf/fusion-pixel-font](https://api.github.com/repos/TakWolf/fusion-pixel-font)

### Inferences
- The 8 px Japanese kanji the app already ships are Misaki's, so adding Misaki Gothic would duplicate them. Misaki Mincho and Misaki Gothic 2nd differ only in kana and half-width glyphs.
- M+ BITMAP / PixelMplus at 10 and 12 px are separate designs from Ark Pixel and would be a second plain gothic at sizes already covered; lower priority than new sizes and styles.
- The Fusion README does not name the Latin/base source at 8 px, and I did not check whether Ark Pixel itself borrows from any Japanese font.

### Gaps
- The Ark Pixel 16 px data from release 2026.09.01 is still OFL and still downloadable in principle, but its Japanese completeness was never stated, and I did not check the old release.

## Key question 5: Curated lists, kana-only fonts, tiny-size experiments, paid fonts, provenance

### Takeaway
No dedicated "awesome Japanese pixel fonts" list turned up; the JF Dot page and a GBA homebrew font list are the useful indexes. No font found is described as ripped from a console or arcade ROM, though several deliberately imitate that look, and one family started as a commercial product that its designer later opened.

### Cited Findings
- laqieer/gba-free-fonts "others.md" lists free 1bpp dot-matrix fonts with license and size: GNU Unifont (16x16), WQY Bitmapsong (9 to 12 pt, GPL), Unscii, littlelimit (12x8, 8x12, 8x8, 6x8; "Unlimited permission"), Shinonome (12/14/16, Public Domain), IPix, Zpix, Vonwaon Bitmap (12 and 16 px, CC0, 6,763 Chinese characters). — [laqieer/gba-free-fonts](https://www.github.com/laqieer/gba-free-fonts/blob/main/others.md)
- Kana-only or no-kanji (lower priority):
  - x5y8pxNegaTape and x5y8pxNegaClip (hicc, 5x8, OFL 1.1, released 2026-06-13). — [x0y0pxFreeFont](https://hicchicc.github.io/00ff/). Their kanji coverage is not stated; at 5x8 kana-only is likely but unconfirmed.
  - もさもさフォント: 8x8, hiragana, katakana, alphanumerics and symbols; free for commercial and non-commercial use if the author's copyright notice is shown; described as recalling Famicom game lettering. — secondary, from a search summary of [Impress Forest review](https://forest.watch.impress.co.jp/docs/review/515208.html)
  - Digital Jots 5x5: CC0, includes katakana and Japanese punctuation. — secondary, [OpenGameArt Digital Jots](https://opengameart.org/content/digital-jots-5x5-pixel-font-with-katakana)
  - ひとりっこ (213-niimi-hitoricco): free version is Latin and katakana only; the version with kanji costs 1,000 yen. Not confirmed to be a pixel font. — secondary, from a search summary of [Impress Forest news](https://forest.watch.impress.co.jp/docs/news/2147369.html)
- Tiny kanji: the smallest kanji-bearing fonts found are 5x5 ノスタルジア (2,398 characters in total, kanji subset size not stated) and k6x8 (5x7 body, JIS level 1 and 2). Misaki is the 7x7-body option. — [BOOTH 5x5 ノスタルジア](https://booth.pm/ja/items/4442315); [littlelimit.net k6x8](https://littlelimit.net/k6x8.htm); [littlelimit.net Misaki](https://littlelimit.net/misaki.htm)
- Paid / restricted:
  - Zpix: paid for commercial products (already rejected). — [laqieer/gba-free-fonts](https://www.github.com/laqieer/gba-free-fonts/blob/main/others.md)
  - Nu mochi: free of charge but no redistribution, no distribution of derived glyph data, fixed strings only. — [こかげ Nu mochi page](https://kokagem.sakura.ne.jp/font/mochi/)
  - Naga10, Elisa 8, Pau16: commercial use needs permission that cannot be obtained. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
  - Silver: CC BY 4.0 with a request to buy a license above a $100,000 budget. — [Silver on itch.io](https://poppyworks.itch.io/silver)
  - 横浜ドット: follow-or-repost condition. — secondary, [Impress Forest news](https://forest.watch.impress.co.jp/docs/news/1641883.html)
- Provenance:
  - KH Dot fonts were a commercial product (『電脳フォント』, sold via TAKERU, distributed in X68000 formats); the OFL release is by the designer himself, so the commercial origin is not a concern. — [jikasei.me KH Dot fonts](http://jikasei.me/font/kh-dotfont/)
  - jiskan16 / jiskan24 full-width glyphs trace to JEITA (the JIS standard's reference bitmaps) and are stated public domain; the half-width glyphs in the non-"s"/"h" builds are Sony's and carry a notice requirement. — [jikasei.me JF Dot fonts](http://jikasei.me/font/jf-dotfont/)
  - Misaki was originally designed for a pocket computer, which is why most characters sit on a 7x7 grid; the littlelimit page also lists a "viewfont (MSXView compatible ROM)" entry built from k12x8. — secondary for the pocket-computer origin, [Impress Forest review](https://forest.watch.impress.co.jp/docs/review/518253.html); [littlelimit.net font page](https://littlelimit.net/font.htm)
  - Nu mochi says its above-the-letter dakuten "imitates a characteristic design born under retro-game constraints", and k8x12S is designed around the same 8x8 console limit. These are stylistic imitations of a convention, not copies of a specific ROM font. — [こかげ Nu mochi page](https://kokagem.sakura.ne.jp/font/mochi/); [littlelimit.net k8x12](https://littlelimit.net/k8x12.htm)

### Inferences
- The fonts with the strongest provenance are the ones with a named original designer who made the release decision personally (平木敬太郎 for KH Dot, 門真なむ for littlelimit, hicc, the efont project for Shinonome). The weakest are 2000-era public-domain fonts where the only accessible statement of status is a third party's table.
- The "viewfont (MSXView compatible ROM)" entry is a compatibility replacement for a system ROM font, drawn from the author's own k12x8. It is not listed as a candidate here and would deserve a closer look before any use.

### Gaps
- TakWolf does not appear to publish a list of pixel fonts beyond the upstream tables in his READMEs; none was found.
- Japanese roundup blogs for "ドットフォント フリー 商用可" did not surface in search; results were dominated by individual BOOTH items and Impress news.
- No 4x4 kanji font was found. No clearly licensed kanji font at exactly 7, 9 or 11 px was found other than LanaPixel (11 px, legibility caveat, unverified coverage).
- Whether any candidate reproduces glyphs from a specific commercial system font (for example a PC-98 or X68000 ROM) cannot be judged from license pages; it would need a visual comparison.
