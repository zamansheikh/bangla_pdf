## 1.8.0

Reads the documents it previously refused: ones that carry no text, and ones
that are encrypted.

### Added

- **Encrypted PDFs are decrypted.** Most "protected" documents — the kind a
  government office publishes — carry an owner password to discourage editing
  and an empty user password, so they open without one. Every revision in the
  wild is handled: RC4 40- and 128-bit (revisions 2 and 3), AES-128
  (revision 4) and AES-256 (revisions 5 and 6). `extract` takes a `password:`
  for a document that genuinely needs one, and `ExtractionResult.isLocked`
  distinguishes "could not be opened" from "is encrypted", which are no longer
  the same thing.

  The ciphers are implemented here rather than pulled in: `package:crypto`
  (already in the tree, now a direct dependency) has MD5 and SHA-2 but no block
  ciphers. AES and RC4 are checked against the FIPS-197 and published test
  vectors, and the handler itself against fixtures encrypted by **qpdf**, so it
  is tested against another implementation rather than its own assumptions.

- **GSUB type 8 and GPOS type 3.** Reverse chaining substitution and cursive
  attachment, the two lookup types the engine was missing, plus the `curs`
  feature in HarfBuzz's order. No Bengali font uses either — asserted by a
  test, not assumed — so nothing about Bangla changes; a font that does use
  them is no longer shaped wrongly with no sign of it. GSUB 8 is verified
  against HarfBuzz using Noto Sans Coptic, which puts one in `ccmp`.

### Added

- **Un-shaping.** A document with no `/ToUnicode` CMap and no `/ActualText` has
  thrown its text away; all that survives is which glyph was drawn. Such a
  document is now read by taking the embedded font apart backwards: every
  `GSUB` substitution it declares — single, multiple, alternate and ligature,
  including through extension lookups — is inverted into "this glyph came from
  those", then resolved until each glyph is expressed as codepoints the `cmap`
  knows.

  Decoding alone is not enough, because Bengali draws a cluster out of order,
  so reph and pre-base vowel signs are moved back into typing order and the
  pairs Unicode writes as one character are recomposed.

  **243 of 251 corpus cases (97%)** come back exactly. The shortfall is text
  that is not in the glyphs at all: an emoji the font cannot draw, a ZWJ (which
  is invisible), and the dotted circles the shaper inserts for a vowel sign
  typed with no consonant.

  It is used only as a last resort. A document that carries a real `/ToUnicode`
  is unaffected — that is authoritative, where this is inference.

- `/CIDToGIDMap` streams are honoured, so a CID font that remaps its glyphs is
  read correctly rather than by assuming identity.

### Verification

- **The corpus is now compared as pixels, not only as glyph ids.** 238 cases
  are drawn by this package and by HarfBuzz, rasterised by the same poppler at
  the same size, cropped to their ink and overlaid: **98.1% mean overlap, 91.4%
  at worst**. Glyph-level parity cannot see a wrong advance written into the
  embedded font, or a glyph drawn at the wrong offset; this can.

  Two things had to be right for the comparison to mean anything. The images
  are nudged a couple of pixels against each other before scoring, because
  cropping aligns only to whole pixels while glyphs land on sub-pixel
  boundaries — without it, a half-pixel offset shears away a large share of
  the overlap on a script made of thin strokes. And `hb-view` is given
  `--script=Beng`: left to guess, it picks Latin for any string starting with
  Latin and skips Indic shaping altogether, which made correct output look
  like a defect in four cases until it was checked.

- Chrome, Brave and Adobe Reader confirmed to copy and paste shaped Bangla
  correctly. Previously only poppler had been checked.
- Three real PDFs from a Bangladeshi government primary-education site (52
  pages) were run through extraction. All three are pure scans, and all 52
  pages were reported as having no text layer rather than given invented text.
  `test/real_documents_test.dart` runs over anything placed in
  `test/fixtures/real/`, and skips when it is empty.

### Notes

- Inverting `GSUB` cannot always tell which side of a consonant its virama
  belongs on: a reph is typed `র` then virama and a ya-phala the other way
  round, yet a font lists both the same way. Rather than guess, a decode is
  confirmed by shaping it again and keeping it only if the same glyphs come
  back; where they do not, virama positions are flipped until they do. That
  search is bounded, so a long ambiguous run keeps its unverified reading
  rather than costing exponential time.
- If a producer's subsetter dropped `GSUB`, only what the `cmap` reaches can be
  recovered. This package's own subsetter drops it too, which is harmless
  because its documents always carry `/ActualText`.

## 1.7.0

Documents are now a fraction of their former size: only the glyphs actually
drawn are embedded.

### Added

- **Font subsetting.** A Bengali font is mostly outlines — `glyf` is 85% of the
  bundled Kalpurush and 62% of Noto Sans Bengali — and a document draws a few
  dozen of them. The shaping tables are dead weight in a PDF as well, since
  shaping has already been applied before anything is written, so `GSUB`,
  `GPOS` and `GDEF` are dropped along with the screen-hinting tables and the
  8 KB glyph-name table in `post`.

  | | before | after |
  |---|---|---|
  | one line of Bangla | 73 KB | **5 KB** |
  | a paragraph | 73 KB | **11 KB** |
  | a paragraph with a fallback font | 222 KB | **17 KB** |
  | the four sample documents | ~78 KB each | **13–18 KB** |

  This matters most for 1.6.0's fallback chains, where every extra font used to
  add its full weight.

  Glyph ids are preserved rather than renumbered, so `/CIDToGIDMap`, the `/W`
  array and `/ToUnicode` are untouched; the cost is four bytes of `loca` per
  blanked glyph against hundreds saved per dropped outline. Composite glyphs
  pull in the glyphs they are built from, transitively. Embedded fonts now
  carry the conventional `ABCDEF+` subset tag.

  A font that cannot be cut safely — PostScript/CFF outlines, a damaged table
  directory — is embedded whole rather than risked.

### Verification

Rendering was checked, not assumed: the four sample documents rasterise
**byte-identically** to their pre-subsetting renders at 220 dpi. Extraction
alone could not have caught a dropped outline, since `/ActualText` carries the
source text whether or not a glyph was drawn.

Seven new tests, including every corpus case rendered through a subset font,
and a composite glyph requested alone to prove its components survive.

## 1.6.0

Characters your Bangla font does not have now render, and the three `Text`
options that were being ignored are honoured.

### Added

- **Font fallback.** `TextStyle.fontFallback` is honoured, and
  `BanglaPdf.configure(fallbackFonts: [...])` sets a chain for the whole
  document. Each character is drawn by the first font in the chain that has a
  glyph for it.

  This is the fix for missing characters generally. Measured across the five
  tested faces, no Bangla typeface contains arrows, symbols or emoji, and most
  barely cover Latin-1 — the bundled Kalpurush has 206 glyphs in total, of
  which 8 of 96 Latin-1 and 0 of 128 Latin Extended-A. So `café`, `±`, `°`,
  `€` and emoji were all silently dropped. Swapping the default typeface could
  not have fixed this; only a fallback chain can.

  Bengali is never affected: it is always drawn by the Bangla font, and a
  fallback boundary can never fall inside a cluster, because combining marks
  stay with the base they follow.

- **`tightBounds`** measures real ink now. `OtFont` gained per-glyph extents
  read from `glyf`/`loca`, so the box hugs the glyphs actually drawn instead of
  the font's ascent and descent. A font without TrueType outlines falls back to
  the font metrics.

- **`softWrap: false`** lays the text out on a single line.

- **`textDirection`** resolves `TextAlign.start` and `end` to the correct edge.
  It does not reorder right-to-left text; that needs a bidi pass and is now
  stated as a limitation rather than left to be discovered.

### Fixed

- `BanglaPdf`'s class documentation claimed the bundled font was Noto Sans
  Bengali. It is Kalpurush, as it has been since 1.0.

### Notes

- The bundled typeface is unchanged. Kalpurush stays the default so existing
  documents keep their appearance; a fallback chain is the supported way to
  widen coverage.

## 1.5.0

Long Bangla documents and justified Bangla text both work now. These were the
two largest gaps between shaped text and what `package:pdf` does with Latin.

### Added

- **Bangla text spans pages.** `ShapedTextWidget` implements
  `SpanningWidget`, so inside a `pw.MultiPage` a paragraph marked
  `overflow: TextOverflow.span` continues onto the next page, breaking on a
  line boundary. Previously it threw:

  ```
  PdfException: Widget won't fit into the page as its height (665.28)
  exceed a page height (220.0). You probably need a SpanningWidget
  ```

  which made multi-page reports and notices — the package's main use case —
  impossible with a paragraph longer than one page. Spanning is opt-in through
  `overflow: TextOverflow.span`, exactly as it is for `pw.RichText`, so no
  existing document changes.

- **`TextAlign.justify` justifies.** It previously fell through to left
  alignment, silently: `pw.Paragraph` *defaults* to justify, so most callers
  were getting ragged text without being told. Slack is shared between word
  gaps and the last line of each paragraph is left ragged, as in any
  typesetting system. Extraction is unaffected — a justified line and a ragged
  one produce identical text.

### Changed

- The showcase notice and report now show genuinely justified body text.

### Notes

- `textDirection`, `softWrap` and `tightBounds` are still ignored once a string
  is shaped; they are honoured on the `package:pdf` path. This is now stated in
  the README rather than left to be discovered.

## 1.4.3

### Fixed

- **Compat widgets reported zero height.** `package:pdf`'s
  `TextStyle.lineSpacing` is extra leading in points and defaults to `0`, while
  `ShapedTextWidget`'s is a multiplier. The bridge passed one straight into the
  other, so every shaped line computed a height of zero: text still painted,
  but any `Column`, `Container` or `Table` around it laid out as if the text
  were not there, and neighbouring widgets overlapped.

  `ShapedTextWidget` now takes `extraLeading` separately, and the compat layer
  maps `TextStyle.lineSpacing` onto it — so `lineSpacing: 8` adds 8 points, as
  it does in `package:pdf`. A compat widget's box now matches the original
  API's exactly.

  Only `package:bangla_pdf/widgets.dart` (new in 1.4.0) was affected. The
  original `Text`, `Header`, `Table` and friends were never wired this way.

### Added

- A fourth showcase document — a half-yearly report with metric cards and a bar
  chart carrying Bangla axis labels and a Bangla legend. It is written against
  the drop-in entry point, so `tool/dev/make_showcase.dart` now exercises both
  APIs the package offers.
- Two layout regression tests pinning the box a shaped widget reports, and the
  meaning of `lineSpacing`.

### Changed

- README shows the four sample documents two per row.
- The first pub.dev screenshot is now a full sample document rather than the
  before/after comparison.

## 1.4.2

Fixes font selection through the new `widgets.dart` entry point.

### Fixed

- **A legacy Bijoy font passed to a compat widget was silently ignored** and
  replaced with the bundled Unicode Kalpurush, so 1.0.x documents moved to the
  new entry point would have changed typeface without warning. A font is now
  classified by what it contains — whether its `cmap` covers Bengali, and how
  densely it covers the Latin-1 supplement — so a Bijoy face is recognised and
  drives the transcoding path with *that* font, as it does in the original API.

### Added

- A plain `pw.Font.ttf` covering Bengali is **promoted to a shaping font**,
  both in a `TextStyle` and in `BanglaPdf.configure(defaultFont:)`. Callers no
  longer have to know that `BanglaPdf.loadFont` exists; either works.
- Six tests covering every font route: no font, `loadFont`, a plain Bangla
  `pw.Font.ttf`, two Bijoy faces, and a Latin-only font.

### Changed

- README: the "Want a different font?" section showed `Text(banglaFont: …)`,
  which is the original API and does not compile against the `pw`-shaped
  widgets the rest of the page now uses.

## 1.4.1

- README: the drop-in section rewritten in plain language, and the three sample
  documents re-rendered at 220dpi so they are readable at full width. The higher
  resolution files are also smaller — 104 KB the set, down from 178 KB.

## 1.4.0

Adds a second entry point that makes this package a true drop-in for
`package:pdf`: change one import and existing code renders Bangla correctly.

### Added

- **`package:bangla_pdf/widgets.dart`** — a replacement for
  `package:pdf/widgets.dart`. It re-exports everything `package:pdf` exports,
  with the text-rendering widgets swapped for versions that shape Bangla and
  take exactly the same parameters:

  ```diff
  - import 'package:pdf/widgets.dart' as pw;
  + import 'package:bangla_pdf/widgets.dart' as pw;
  ```

  Replaced: `Text`, `RichText`, `TextSpan`, `Header`, `Paragraph`, `Bullet`,
  `TableHelper`, `Watermark`, `TableOfContent`, `ChartLegend`, `FixedAxis`,
  `TextField` and `ChoiceField` — every widget in `package:pdf` that builds a
  `Text` internally, so chart labels, watermarks, tables of contents and form
  field values all shape too.

  A string with no Bengali in it is passed to `package:pdf` untouched, so a
  document without Bangla renders exactly as it does without this package.

- `tool/dev/check_pw_parity.py`, which diffs all 14 replacement constructors
  against their `package:pdf` counterparts. All 156 parameters match.

- `test/compat_test.dart` (8 tests). It never imports `package:pdf/widgets.dart`,
  so a gap in the re-export or a renamed parameter fails the build rather than
  reaching a user.

### Fixed

- `BanglaShapingMode.legacy` now routes the compatibility widgets through the
  1.0.x Bijoy pipeline. Reaching that mode through the new entry point would
  otherwise have drawn raw Unicode with a Latin font.

### Notes

- The existing `bangla_pdf.dart` widgets (`Text`, `Header`, `BulletList`,
  `Table`, …) are unchanged and unaffected. Nothing is deprecated by this
  release; the two entry points can be mixed in one file.
- Form fields shape their appearance stream only. Once a reader lets someone
  edit the field it re-renders from the form font, which no producer controls.

## 1.3.1

Completes signature parity with `package:pdf` and rewrites the README around
real example documents.

### Added

The last parameters that were still missing from a `pw` counterpart. All
optional, so no existing call changes.

- `Text`, `AutoText`, `RichText` — `hyphenation`.
- `Header` — `child`, matching `pw.Header`.
- `TextSpan` — `baseline` and `annotation`, matching `pw.TextSpan`.
- `BulletList` — `bulletSize`, `bulletShape`, `bulletMargin`. Setting
  `bulletSize` draws a shape marker instead of a text bullet, as `pw.Bullet`
  does.
- `Table` — `headerAlignments`, `cellDecoration`, `textStyleBuilder`,
  `cellBuilder`, completing `pw.TableHelper.fromTextArray`.

### Changed

- README rewritten to lead with example output and keep the shaping internals
  in collapsible sections.
- Three new screenshots — an invoice, a notice and a report — generated from
  the public widgets by `tool/dev/make_showcase.dart`. They replace the old
  single-page widget preview.

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
