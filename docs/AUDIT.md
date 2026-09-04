# AUDIT — Bangla shaping rules vs. what each package implements

Phase 1 deliverable. Compares:

| | version audited | mechanism |
|---|---|---|
| **`bangla_pdf`** | 1.0.6 (this repo, unmodified) | Unicode → Bijoy-ANSI transcode + 231-glyph legacy 8-bit font |
| **`bangla_pdf_fixer`** | **3.1.1** (read from `~/.pub-cache`) | real HarfBuzz shaping via FFI, glyphs drawn as **vector outlines** |
| **`pdf_text_shaper`** | 1.1.0 | the engine `bangla_pdf_fixer` 3.x delegates to |

---

## 0. Correction to the brief

The task brief states that *"the current `bangla_pdf` 1.0.6 and the competing
`bangla_pdf_fixer` both rely on glyph reordering hacks (BanglaUnicodeMapper /
FixingUtils), not real GSUB/GPOS shaping."*

That was true of `bangla_pdf_fixer` 2.x. It is **not true of 3.x**, which shipped a
rewrite. From its own CHANGELOG for 3.0.0: *"Rebuilt Bangla rendering on top of
`pdf_text_shaper`. Replaced legacy ANSI mapping with Unicode-first HarfBuzz shaping."*
`pdf_text_shaper` 1.1.0 links real HarfBuzz through `harfbuzz_ffi` and calls
`hb_shape()` (`harfbuzz_shaper.dart:76`) — so GSUB **and** GPOS are fully applied,
by HarfBuzz itself, on all five native platforms.

So the competitive gap is real but different from the brief's framing. It is not
"they reorder, we shape". It is:

| | `bangla_pdf_fixer` 3.1.1 | opportunity for `bangla_pdf` |
|---|---|---|
| shaping correctness | **excellent** (HarfBuzz) | match it |
| web / WASM | **unsupported** (`platforms:` lists android, ios, linux, macos, windows only; FFI + native build hook) | **we can support web** |
| text in the PDF | glyphs are **vector paths**; real text only as an optional *invisible* overlay (`preserveUnicodeText`) drawn at run granularity | **emit real Type0 glyphs with a correct multi-char `/ToUnicode`** — selectable, searchable, exact |
| file size | every glyph occurrence re-emits its outline into the content stream (outline cache is in-memory only), **and** the full font is embedded when `preserveUnicodeText` is on | subset font, one CID per glyph |
| missing glyph | **throws `StateError`** and kills PDF generation | fall back |
| build requirements | Dart ≥ 3.13, native build hooks, a C toolchain | pure Dart by default |
| zero-config default font | none — fonts must be supplied | keep our embedded font |

Those five columns, not shaping correctness alone, are where "first Flutter package that
gets Bangla right in every case" can actually be won.

---

## 1. Rule-by-rule table

Legend — **✔** correct · **~** partial/conditional · **✘** wrong or absent · **💥** crashes

| # | Shaping rule | OpenType feature | `bangla_pdf` 1.0.6 | how | `bangla_pdf_fixer` 3.1.1 | how |
|---|---|---|---|---|---|---|
| 1 | Independent vowels, bare consonants | — | ✔ | 1:1 entry in `_conversionMap` | ✔ | font `cmap` |
| 2 | Post-base vowel signs `া ী ু ূ ৃ` | `abvs`/`psts` + GPOS | ✔ | 1:1 map entry | ✔ | GSUB+GPOS |
| 3 | Pre-base vowel signs `ি ে ৈ` | reorder + `pres` | ✔ | `_rearrangeUnicodeStr` rule 1, `_isBanglaPreKar` | ✔ | HarfBuzz Indic reorder |
| 4 | Two-part vowels `ো ৌ` | decompose + reorder | ✔ | literal replace to `‡`+`v` / `‡`+`Š` | ✔ | HarfBuzz |
| 5 | Reph (`র` + virama + C) | `rphf` | 💥 | `_rearrangeUnicodeStr` rule 2 — **`RangeError` when the word ends the run** (§5.1 of CURRENT_STATE) | ✔ | `rphf` |
| 6 | Reph + pre-base vowel (`র্তি`) | `rphf` + reorder | 💥 | rule 2's `foundPreKar` path, same crash | ✔ | HarfBuzz |
| 7 | Reph + conjunct + vowel (`র্ত্তি`, `র্ষ্ণে`, `র্ক্ষ্য`) | `rphf`+`cjct`+reorder | 💥 | same crash | ✔ | HarfBuzz |
| 8 | Ya-phala `্য` | `pstf` | ✔ | `"্য": "¨"` | ✔ | `pstf` |
| 9 | Ra-phala `্র` | `blwf`/`vatu` | ✔ | `"্র": "ª"` | ✔ | `blwf` |
| 10 | Ra-phala + ya-phala `্র্য` | `blwf`+`pstf` | ✔ | dedicated entry `"্র্য": "ª¨"` (placed first, so it wins) | ✔ | HarfBuzz |
| 11 | 2-consonant conjuncts in the table (`ক্ষ ক্ত জ্ঞ ষ্ণ দ্ধ ল্ল` …) | `half`/`cjct`/`akhn` | ✔ | ~180 precomposed entries | ✔ | GSUB |
| 12 | 2-consonant conjuncts **not** in the table | `cjct` | ✘ | falls to `"্": "&"` → **visible hasanta** | ✔ | GSUB covers the font's whole repertoire |
| 13 | 3-consonant conjuncts (`ন্ত্র ন্ধ্র ম্ভ্র`) | `cjct` chain | ~ | only where a literal entry exists **and** is not shadowed; `ম্ভ্র` is shadowed by `ভ্র` → broken | ✔ | GSUB |
| 14 | 3-consonant with prefix shadowing (`ঙ্ক্ষ ত্ত্ব চ্ছ্ব ক্ষ্ম`) | `cjct` | ✘ | 7 dead entries + no longest-match (§5.2) | ✔ | GSUB |
| 15 | 4-consonant conjuncts (`স্ত্র্য`) | `cjct` chain | ✘ | renders `স্ত`+ra-phala+ya-phala, not the conjunct | ✔ | GSUB |
| 16 | Explicit/visible hasanta, `ক্‌ষ` with ZWNJ | ZWNJ blocks `cjct` | ~ | ZWNJ is deleted late, but `&` happens to give the right shape | ✔ | HarfBuzz honours ZWNJ |
| 17 | Khanda-ta `ৎ` | `akhn` | ✔ | `"ৎ": "r"` | ✔ | `cmap`/`akhn` |
| 18 | `ত` + virama at end of word | — | ✔ | `Z&` = ta + visible hasanta | ✔ | HarfBuzz |
| 19 | Nukta, precomposed `ড় ঢ় য়` | — | ✔ | direct map entries | ✔ | `cmap` |
| 20 | Nukta, decomposed (C + U+09BC) | `nukt` | ✔ | 3 literal replaces at `_fixFont` lines 17–19 | ✔ | `nukt` |
| 21 | Nukta on other bases (e.g. `ক়`) | `nukt` | ✘ | no rule — U+09BC survives, no ANSI glyph | ✔ | `nukt` |
| 22 | Chandrabindu `ঁ` | GPOS mark | ~ | `"ঁ": "u"` — a fixed-position ANSI glyph, no mark attachment | ✔ | GPOS `mark`/`mkmk` |
| 23 | Anusvara `ং`, visarga `ঃ` | — | ✔ | map entries | ✔ | `cmap` |
| 24 | Mark stacking / collision avoidance | GPOS | ✘ | none — 8-bit font has no GPOS | ✔ | GPOS |
| 25 | Bengali digits `০–৯` | — | ~ | **transcoded to ASCII `0–9`** — the PDF contains Western digits | ✔ | preserved as Bengali |
| 26 | Taka `৳` | — | ~ | mapped to `$`; glyph looks right, **text is `$`** | ✔ | preserved |
| 27 | Danda `।` / double danda `॥` | — | ~ | `।`→`\|`; **`॥` unmapped → notdef** | ✔ | both preserved |
| 28 | Assamese `ৰ` `ৱ` (U+09F0/1) | — | ✘ | unmapped → notdef | ✔ | if the font covers them |
| 29 | ZWJ `র‍্য` vs ZWNJ `র্য` | `rphf` blocking | ✘ | **all ZWJ rewritten to ZWNJ at line 21** before any decision is made | ✔ | HarfBuzz |
| 30 | NFC vs NFD equivalence | normalisation | ~ | only the 3 nukta pairs and `ো`/`ৌ`; no general normaliser | ~ | no NFC pass either — relies on the font's `nukt`/`akhn` |
| 31 | Mixed Bangla + Latin | script itemisation | ~ | regex split; Latin run gets **no font** → base-14 Helvetica | ✔ | per-rune script run splitting |
| 32 | Emoji / non-Latin-1 in the Latin run | font fallback | ✘ | crossed-box placeholder (measured) | ~ | **throws `StateError`** unless a fallback font is registered |
| 33 | Line breaking on grapheme clusters | — | ✘ | `pw.RichText` splits on `\s` and, for an over-wide word, character-by-character via `_splitWord` (`widgets/text.dart:1336`) — over the **ANSI** string, so a break can land between `‡` and the consonant it belongs to | ~ | breaks on whitespace; `characters` used only for oversized tokens |
| 34 | Justification | — | ✘ | not offered | ✘ | `start`/`center`/`end` only |
| 35 | **Copy/paste, search, `pdftotext`** | `/ToUnicode` | ✘ | ANSI Latin-1 (measured, §6 of CURRENT_STATE) | ~ | correct Unicode, but from an **invisible overlay** whose glyph boxes do not match the painted outlines, so selection highlighting and word order under selection are approximate |
| 36 | Bold / italic | font variants | ✘ | `getAutoLocalizedSpans` builds `pw.TextStyle(font: …, fontWeight: bold)`; `pw.TextStyle` then assigns that same single font to `fontBold` (`widgets/text_style.dart:149`) and `package:pdf` never synthesises weight — so `fontWeight` is visually inert | ~ | caller supplies a bold font |
| 37 | Web platform | — | ✔ (renders, wrongly) | pure Dart | ✘ | not supported |

### Scorecard over the 84-case Phase 1 probe corpus

|  | ok\* | broken | notdef | crash |
|---|---|---|---|---|
| `bangla_pdf` 1.0.6 | 62 | 5 | 3 | 14 |

\* "ok" is a **text-level** verdict — the transcode produced a plausible glyph sequence.
It is not a rasterised pass. Per the project ground rules no case is claimed to render
correctly until Phase 4 compares images. Note also that **all 84 cases fail the
copy/paste round-trip**, by construction. Full table in [BASELINE.md](BASELINE.md).

---

## 2. Mechanism comparison

### `bangla_pdf` 1.0.6 — reorder table
Two hand-written reorder rules (pre-base vowel, reph) over a UTF-16 code-unit string,
then 220 ordered `String.replaceAll` calls, then an 8-bit font lookup. No font is
consulted at any point: the same substitutions are applied whatever font the user
passes. Coverage is bounded by the 231 glyphs of Kalpurush ANSI and by whichever
conjuncts someone remembered to add to the table — the source comment
`//If broken then add manually plz...` at
[unicode_mapper.dart:396](../lib/src/utils/unicode_mapper.dart#L396) is an honest
description of the design.

### `bangla_pdf_fixer` 3.1.1 / `pdf_text_shaper` 1.1.0 — real HarfBuzz, outline output
`ShapedFont.fromBytes` builds an `hb_face`/`hb_font` from the TTF bytes and calls
`hb_ot_font_set_funcs`. `HarfBuzzShaper.shape` runs `hb_shape()` and returns glyph ids,
clusters, advances and offsets. `ShapedText.paint` then, for each glyph, replays the
glyph's outline through `hb_font_draw_glyph` as `moveTo`/`lineTo`/`curveTo`/`closePath`
into the PDF content stream (`glyph_outline.dart`), and — only if
`preserveUnicodeText` is set — additionally draws the run's source text with
`PdfTextRenderingMode.invisible` on top.

Two structural consequences worth stating precisely, because they are where a better
design can win:

1. **Outlines are not text.** The visible marks are paths. A viewer's text layer is the
   separate invisible `drawString`, positioned per *run*, not per glyph. Selecting text
   in Preview or Adobe highlights the overlay's boxes, which do not coincide with the
   painted glyphs. `pdftotext -layout` column positions will be off for the same reason.
2. **Outlines are large.** `_cache` in `HarfBuzzGlyphOutlineExtractor` memoises the
   command list in Dart, but `replay` re-emits the full path for **every occurrence** of
   the glyph. A page of Bangla body text re-emits a few hundred Bézier paths. With
   `preserveUnicodeText` on, the full font is *also* embedded (`pw.Font.ttf(byteData)`),
   so you pay for both.

A Type0 CID font with glyph-id-addressed text and a multi-character `/ToUnicode` CMap
avoids both problems and gives exact selection. That is what Phase 3 should emit.

---

## 3. What blocks `bangla_pdf` from emitting glyph-addressed text today

Read from `pdf` 3.13.0 (Apache-2.0):

* `obj/ttffont.dart` `PdfTtfFont` builds a Type0/Identity-H CID font, but
  `unicodeCMap.cmap` is a `List<int>` indexed by CID whose value is a **single rune**,
  and `putText` allocates one CID per rune. There is no path through the public API to
  emit an arbitrary glyph id.
* `obj/unicode_cmap.dart` `PdfUnicodeCmap` writes `beginbfchar` entries of the
  form `<CID> <UUUU>` — one BMP scalar per CID. A ligature like `ক্ষ্ম` needs
  `<CID> <0995 09CD 09B7 09CD 09AE>`, which this class cannot express.
* `font/ttf_writer.dart` `TtfWriter.withChars(List<int> chars)` subsets by
  *character*, resolving through `ttf.charToGlyphIndexMap`. There is no `withGlyphs`.
* `font/ttf_parser.dart` parses `head name hmtx hhea cmap maxp loca glyf CBLC
  CBDT post OS/2` only — **no `GSUB`, no `GPOS`, no `GDEF`**.

None of this is a blocker, because `PdfFont`, `PdfTtfFont` and `TtfParser` are all
exported from `package:pdf/pdf.dart`. Phase 3 needs its own `PdfFont` subclass, its own
`/ToUnicode` writer that supports multi-scalar `bfchar` values, and its own glyph-id
subsetter (or, for a first cut, no subsetting at all). Sizes and trade-offs are in
[adr/001-shaping-engine.md](adr/001-shaping-engine.md).

---

## 4. Licensing notes gathered during the audit

| artefact | license | implication |
|---|---|---|
| `pdf` 3.13.0 | Apache-2.0 | forking `TtfWriter`/`PdfUnicodeCmap` logic into this BSD-3 package is allowed with attribution + NOTICE. Must be stated in the source header and LICENSE. |
| Noto Sans Bengali | OFL-1.1 | bundleable; requires shipping the OFL text and keeping the Reserved Font Name rules. |
| Kalpurush ANSI (currently bundled) | **unverified** | the embedded copy carries **no `name[0]` copyright record and no `name[13]`/`name[14]` license record at all**. Its only provenance string is `name[3] = "PYRS: Kalpurush ANSI: 2010"`. Kalpurush is by Md. Tanbin Islam Siyam, distributed by Omicronlab; the redistribution terms of this ANSI variant need confirming. **Flagged for you** — this affects what we may keep bundling. |
