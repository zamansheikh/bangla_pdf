## 1.1.1

Documentation only. No code changes, so nothing behaves differently.

- Rewrote the README: a rendered before/after generated from the real pipeline,
  a feature grid, section icons, the sample-page screenshot alongside the widget
  list, and a `pdftotext` before/after showing that the text in the PDF is now
  real Bangla rather than Bijoy ANSI.
- Scoped the `bangla_pdf_fixer` credit to the legacy Bijoy pipeline, which is
  what actually descends from it.
- Fixed the screenshot paths: `pubspec.yaml` pointed into a directory excluded
  from the published archive, so the screenshot reference would have dangled.
  Both screenshots now ship.
- The audit and verification write-ups under `docs/` stay in the repository and
  are not shipped in the package; the README links to them by URL.

## 1.1.0

Bangla is now shaped with the font's own OpenType tables instead of being
transcoded to Bijoy ANSI. Conjuncts ligate, reph and pre-base vowel signs are
reordered correctly, and the text in the PDF is real Unicode that copies,
searches and extracts. **No API was removed and no existing call needs
changing.**

### Fixed — crashes

- **`RangeError` on reph.** `কর্ম`, `ধর্ম`, `বর্ষ`, `পূর্ব`, `শর্ত`, `র্ক` and
  any other reph word ending a Bangla run threw an uncaught `RangeError` out of
  `pw.Widget.build`, aborting the whole `pdf.save()`. 21 of the 253 corpus
  cases crashed 1.0.6; none crash now. A lone `ি`/`ে` and a leading `্র`
  crashed for the same reason and are fixed.

### Fixed — shaping

Corpus ids that rendered wrongly in 1.0.6 and are correct now:

- 3- and 4-consonant conjuncts that fell back to a visible hasanta —
  `conj3-01` ক্ষ্ম, `conj3-02` ঙ্ক্ষ, `conj3-05` ত্ত্ব, `conj3-06` চ্ছ্ব,
  `conj3-04` ম্ভ্র, `conj4-00` স্ত্র্য, `conj4-01` ঙ্ক্ষ্য, `conj4-02` ক্ষ্ম্য.
- Seven conjunct entries in the old table were unreachable because a shorter
  key consumed the input first (`ঙ্ক্ষ`, `চ্ছ্ব`, `ত্ত্ব`, `ন্দ্ব`, `ম্ভ্র`,
  `ষ্ক্র`, `স্তু`). Conjunct coverage now comes from the font, not a table.
- `reph-00` … `reph-19` and `rephconj-00` … `rephconj-07`: reph is placed by
  the font's `rphf` feature and the Indic reordering rules.
- `assamese-00` … `assamese-02` (`ৰ` `ৱ`) and `punct-01` (`॥`) had no mapping
  and rendered as notdef.
- `digits-*`: Bengali digits `০–৯` stayed Bengali instead of being converted to
  ASCII, and `৳` stays `৳` instead of becoming `$`.
- `zwj-00` … `zwj-05`: ZWJ is no longer rewritten to ZWNJ before the shaping
  decision, so `র‍্য` and `র্য` differ correctly.
- `norm-00` … `norm-05`: NFC and NFD spellings now shape identically.
- `mix-*`: Latin, Bengali digits and currency render in one pass with a real
  font instead of falling back to base-14 Helvetica.

### Fixed — the PDF itself

- Text is emitted as a `/Type0` `/Identity-H` CID font addressed by glyph id,
  with a `/CIDToGIDMap` and a `/ToUnicode` CMap whose entries may be several
  codepoints, so a conjunct copies back as its full sequence.
- Each line is wrapped in a `/Span <</ActualText …>> BDC … EMC` span, which is
  what makes copy/paste survive Bengali's glyph reordering. `pdftotext`
  recovers 249 of 251 corpus cases exactly; 1.0.6 recovered none.
- Line breaking happens on syllable boundaries, so a line can never break
  inside a conjunct or between a vowel sign and its consonant.
- `BulletList` draws its bullet with a real font instead of Helvetica, which
  has no glyph for `•`.

### Added

- `BanglaShapingMode` (`auto`, `unicode`, `legacy`) and
  `BanglaPdf.configure({shapingMode, defaultFont})`.
- `BanglaPdf.loadFont(ByteData)` for a custom Unicode Bangla font.
- `String.shapeForPdf(font)` for callers building their own PDF content.
- `BanglaPdf.covers(font, text)` to ask whether a font can draw a string.
- `BanglaFontManager().legacyFont` exposes the bundled Bijoy/ANSI font.
- The bundled font is now the **Unicode** build of Kalpurush (OFL-1.0),
  subsetted to 121 KB with all OpenType layout retained. Same typeface as
  1.0.x, so documents look unchanged. Licence in `LICENSE-FONTS.txt`.
- 253-case test corpus in `test/corpus/bangla_cases.json`; 18 automated tests.

### Changed

- **The default font is the Unicode build of Kalpurush instead of the 8-bit
  Bijoy build.** The typeface is identical, so existing documents look the
  same; only the shaping is fixed. Pass
  `BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy)` to restore
  byte-identical 1.0.x output.
- `BulletList` falls back from `•` to a marker the font has, because Kalpurush
  carries no U+2022.
- A `banglaFont:` that is a legacy 8-bit font (SutonnyMJ, Kalpurush ANSI) is
  detected automatically and keeps the 1.0.x pipeline, so existing custom-font
  code is unaffected.

### Verified

- Shaping is identical to HarfBuzz — same glyphs, same positions — on all 234
  pure-Bangla corpus cases, for all three test fonts: the bundled Kalpurush,
  Noto Sans Bengali and Noto Serif Bengali.
- 249 of 251 corpus cases round-trip through `pdftotext` exactly. The two
  exceptions are one artefact: a lone ZWJ renders as nothing, so the
  line-by-line comparison shifts.

### Known limitations

See the README. In short: PDFs embed the full font rather than a per-document
subset, rendering is not pixel-diffed, copy/paste is verified with poppler
only, and PDF text extraction (`extract.dart`) is not implemented yet.

## 1.0.6

- **FIX**: Fixed some broken character mappings in the Kalpurush font for better rendering.

## 1.0.5

- **FIX**: Fixed some broken character mappings in the Kalpurush font for better rendering.

## 1.0.4

- **DOCS**: Added comprehensive documentation for public API.
- **FIX**: Fixed formatting issues to comply with Dart formatter.
- **EXAMPLE**: Verified example app structure for pub.dev analysis.

## 1.0.3

- **BREAKING**: Removed bundled fonts (except Kalpurush) to reduce package size.
- **BREAKING**: Removed `BanglaFontManager` initialization requirement.
- **BREAKING**: Removed `BanglaFontType` enum. Use `pw.Font` directly for custom fonts.
- **NEW**: `Text` and other widgets now accept `banglaFont` parameter for custom fonts.
- **NEW**: Default font (Kalpurush) is now embedded and loaded automatically.

## 1.0.2

- **NEW**: Added `BanglaAutoText` widget for automatic Bangla and English text mixing
- **ENHANCED**: Updated `BanglaTable` to support mixed Bangla and English content in all cells
- **NEW**: Added support for Bangla Taka symbol (৳) in text rendering
- **FIXED**: Resolved all lint errors - improved code quality and maintainability
- **IMPROVED**: Enhanced Unicode mapping for better character rendering
- **CHANGED**: Switched from Apache 2.0 to MIT License
- **DOCS**: Added comprehensive examples for all widgets with proper documentation

## 1.0.1

- Minor bug fixes and stability improvements.

## 1.0.0

- Initial release of the **Bangla PDF** package 2025-11-20.
- Added support for multiple Bangla fonts.
- Implemented font fixing for PDFs with broken fonts.
- Fixed various issues with font rendering.
