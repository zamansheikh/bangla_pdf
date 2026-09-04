## 1.3.0

Makes the widgets drop-in replacements for their `package:pdf` counterparts, so
Bangla is the only thing that changes when you switch.

### Changed

- **`pdf` is now `^3.13.0`** (was `^3.11.3`). `lib/src/pdf/shaped_pdf_font.dart`
  reaches into `package:pdf`'s internals to build a glyph-addressed CID font, so
  the narrower range is what is actually tested. If you are pinned below 3.13,
  stay on 1.2.0.

### Added

Every one of these is optional, so no existing call changes.

- `Header` — `level`, `title`, `margin`, `padding`, `decoration`, `textStyle`,
  `outlineColor`, `outlineStyle`, matching `pw.Header`.
- `Paragraph` — `margin`, `padding`, matching `pw.Paragraph`.
- `RichText` — `textDirection`, `softWrap`, `tightBounds`, `textScaleFactor`,
  `maxLines`, `overflow`, matching `pw.RichText`.
- `TextSpan` — `style`, matching `pw.TextSpan`. It takes precedence over the
  loose `fontSize` / `color` / `fontWeight` arguments.
- `BulletList` — `bulletColor`, `margin`, `padding`, `itemSpacing`, `textAlign`.
- `Table` — `headerCount`, `headerStyle`, `headerPadding`, `headerHeight`,
  `headerDecoration`, `headerTextColor`, `cellStyle`, `cellTextColor`,
  `cellHeight`, `cellAlignments`, `rowDecoration`, `oddRowDecoration`, `border`,
  `defaultColumnWidth`, `tableWidth`, `defaultVerticalAlignment`, mirroring
  `pw.TableHelper.fromTextArray`.

`Text` already accepted the whole of `pw.Text`'s parameter list and is
unchanged.

### Deprecated

Nothing is removed; both still work and are covered by tests.

- **`AutoText`** — `Text` is now identical to it. It existed to split a string
  into Bangla and non-Bangla runs so each could get its own font; since 1.1.0 a
  Unicode Bangla font covers Latin and digits too, so there is nothing left to
  split. `Text` absorbed its one extra parameter, `generalFont`. Scheduled for
  removal in 2.0.0.
- **`RichTextItem`** — declared in 1.0 and never constructed by anything, in
  this package or in any documented usage. Use `TextSpan` with `RichText`.
  Scheduled for removal in 2.0.0.

### Notes

- Header and Paragraph take their text **positionally**, as they have since
  1.0, where `pw.Header` and `pw.Paragraph` take it as a named `text:`
  argument. That is the one call-site difference.
- `Paragraph` keeps `TextAlign.start` as its default rather than `pw`'s
  `justify`, because changing it would alter existing documents.
- On the shaping path a single font draws the whole string, so `style` and
  `banglaStyle` no longer style Bangla and Latin differently within one widget;
  `banglaStyle` wins when both are set. Use separate widgets for two looks. The
  legacy Bijoy path is unchanged.
- A new `test/api_parity_test.dart` constructs every widget with its full
  parameter set, so a dropped or renamed parameter fails the build.

## 1.2.0

Adds PDF text extraction, in a separate library so generation-only users pay
nothing for it.

```dart
import 'package:bangla_pdf/extract.dart';
final result = BanglaPdfExtractor.extract(bytes);
```

### Added

- `BanglaPdfExtractor.extract(bytes, {ocrHook})` returning `ExtractionResult`
  with `text`, `pages`, `encodingDetected` (`unicode` / `bijoy` / `mixed` /
  `none`), `confidence` and `isEncrypted`.
- **Bijoy / ANSI → Unicode.** Most Bangladeshi government and newspaper PDFs
  store Latin-1 mojibake and rely on an 8-bit font to draw Bangla. These are now
  detected from the embedded font's coverage and converted back, including the
  reverse reordering: pre-base vowel signs move back after their consonant and a
  reph moves back in front of its cluster. Also exposed on its own as
  `bijoyToUnicode`.
- **Scanned-page handling.** A page with images and no text layer reports
  `BanglaTextEncoding.none` instead of guessing, and `ocrHook` lets you plug in
  an OCR engine. None is bundled; the README shows a Tesseract `ben` example.
- A PDF reader covering cross-reference tables and streams, object streams,
  `FlateDecode` (with PNG and TIFF predictors), `LZWDecode`, `ASCIIHexDecode`,
  `ASCII85Decode` and `RunLengthDecode`. A damaged cross-reference table falls
  back to scanning the file for objects, so partly-corrupt documents still read.
- Ten fixture documents with ground truth, and 12 extraction tests.

### Verified

- All 8 extractable fixtures recover their ground truth exactly; both scans are
  correctly reported as having no text layer.
- 245 of 247 pure-Bangla corpus cases survive a Bijoy round-trip. The shortfall
  is the joiner in `বাক্‌`, which the Bijoy encoding cannot represent.

### Changed

- New dependency on `archive` for stream inflation, chosen over `dart:io` so
  extraction also works on web.

## 1.1.2

_Never released on its own; these changes ship as part of 1.2.0._

- **FIX**: Fonts that declare only the version 1 Indic script tag (`beng`)
  rather than `bng2` now shape correctly. **SolaimanLipi** is the notable one:
  it formed no ya-phala or ra-phala at all and left a bare virama behind, so
  `ব্য` `ক্র` `প্র` `স্ত্র` and every conjunct built on a phala came out wrong.
  Version 1 fonts write their `half`/`blwf`/`pstf` rules as *consonant +
  virama*; the shaper now moves the virama after the last consonant of the
  syllable for those fonts, and applies `half` alone before the base rather
  than `half`+`blwf`. SolaimanLipi goes from 183/234 to **234/234** against
  HarfBuzz, with no change to any version 2 font.
- **VERIFIED**: Siyam Rupali matches HarfBuzz on all 234 cases with no changes
  needed. Both bundled ANSI fonts are correctly detected as legacy and routed
  to the Bijoy pipeline by `BanglaShapingMode.auto`.
- Five fonts are now covered by the corpus tests, spanning both generations of
  the OpenType Indic spec.

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
