<h1 align="center">bangla_pdf</h1>

<p align="center">
  <strong>Bangla PDFs that actually look right.</strong><br>
  Change one import. Everything else stays exactly as it is.
</p>

<p align="center">
  <a href="https://pub.dev/packages/bangla_pdf"><img src="https://img.shields.io/pub/v/bangla_pdf.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/bangla_pdf/score"><img src="https://img.shields.io/pub/points/bangla_pdf" alt="pub points"></a>
  <a href="https://github.com/zamansheikh/bangla_pdf/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg" alt="license"></a>
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey" alt="platforms">
</p>

<p align="center">
  <a href="https://pub.dev/packages/bangla_pdf"><img src="https://github.com/zamansheikh/bangla_pdf/raw/main/images/StandWithPalestine.svg" alt="Stand With Palestine"></a>
</p>

---

Write Bangla, get Bangla.

```dart
pw.Text('আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।')
```

That is the `package:pdf` widget you already use, from an import that shapes
Bangla properly. Conjuncts join, `ি` `ে` `ৈ` land on the
correct side of their consonant, reph sits where it belongs — and the text you
copy out of the PDF is the text you put in.

![Before and after](https://github.com/zamansheikh/bangla_pdf/raw/main/images/before-after.png)

---

## 📄 Made with it

Real output from the widgets below — no mockups.

<p align="center">
  <img src="https://github.com/zamansheikh/bangla_pdf/raw/main/images/sample-invoice.png" alt="Invoice" width="31%">
  &nbsp;
  <img src="https://github.com/zamansheikh/bangla_pdf/raw/main/images/sample-notice.png" alt="Notice" width="31%">
  &nbsp;
  <img src="https://github.com/zamansheikh/bangla_pdf/raw/main/images/sample-report.png" alt="Report" width="31%">
</p>

<p align="center">
  <sub>
    <b>Invoice</b> — table, Bengali digits, ৳ &nbsp;·&nbsp;
    <b>Notice</b> — headings and bullets &nbsp;·&nbsp;
    <b>Report</b> — Bangla and English mixed
  </sub><br>
  <sub>Built by <a href="https://github.com/zamansheikh/bangla_pdf/blob/main/tool/dev/make_showcase.dart"><code>tool/dev/make_showcase.dart</code></a></sub>
</p>

---

## 🚀 Get started

```yaml
dependencies:
  bangla_pdf: ^1.4.0
```

Now change one import:

```diff
- import 'package:pdf/widgets.dart' as pw;
+ import 'package:bangla_pdf/widgets.dart' as pw;
```

**That is the entire migration.** Your existing code is untouched:

```dart
import 'package:bangla_pdf/widgets.dart' as pw;

final pdf = pw.Document();

pdf.addPage(
  pw.Page(
    build: (context) => pw.Text('আমার সোনার বাংলা'),
  ),
);

final bytes = await pdf.save();
```

No font to bundle, nothing to initialise, no new widget names to learn. A Bangla
font ships with the package and is used automatically.

---

## 🧩 It really is the same API

`package:bangla_pdf/widgets.dart` re-exports everything `package:pdf` gives you.
The widgets that draw text are swapped for versions taking **exactly** the same
parameters — checked constructor by constructor on every build, all 156 of them
across 14 constructors:

| replaced | so this keeps working |
|---|---|
| `pw.Text` `pw.RichText` `pw.TextSpan` | `pw.Text('বাংলা', maxLines: 2)` |
| `pw.Header` `pw.Paragraph` `pw.Bullet` | `pw.Header(level: 1, text: 'শিরোনাম')` |
| `pw.TableHelper.fromTextArray` | `pw.TableHelper.fromTextArray(data: …)` |
| `pw.Watermark` `pw.TableOfContent` | `pw.Watermark.text('গোপনীয়')` |
| `pw.ChartLegend` `pw.FixedAxis` | Bangla chart labels and legends |
| `pw.TextField` `pw.ChoiceField` | Bangla in form fields |

Everything else — `pw.Page`, `pw.Column`, `pw.Container`, images, barcodes,
`pw.MultiPage` — is the same class you were already using.

```dart
pw.Header(level: 1, text: 'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার')

pw.Paragraph(text: 'একটি অনুচ্ছেদ যেখানে ক্ষ্ম ও কর্ম দুটোই ঠিক আসে।')

pw.Bullet(text: 'প্রথম আইটেম')

pw.TableHelper.fromTextArray(
  headers: ['পণ্য', 'পরিমাণ', 'মূল্য'],
  data: [
    ['কফি', '২', '৳২০'],
  ],
)
```

Bangla, English, digits and `৳` mix freely in one string — nothing to split up
by hand:

```dart
pw.Text('Invoice #1042 — মোট ৳১২,৫০০.০০ — তারিখ ০১/০৯/২০২৬')
```

**A string with no Bangla in it never touches this package.** It is handed
straight to `package:pdf`, so your English pages render exactly as they do
today.

<details>
<summary>Prefer explicit widgets? Those still exist.</summary>

If you would rather see at a glance which widgets are Bangla-aware, import the
main library instead and use its own widgets. This is the original 1.0 API and
it is not going anywhere:

```dart
import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Text('বাংলা টেক্সট')
Header('বাংলা শিরোনাম', level: 1)
Paragraph('একটি অনুচ্ছেদ।')
BulletList(items: ['প্রথম আইটেম', 'Second item'])
Table(data: [['পণ্য', 'মূল্য'], ['কফি', '৳২০']])
RichText(spans: [TextSpan('বাংলা বোল্ড ', fontWeight: pw.FontWeight.bold)])
```

These differ slightly from `pw` on purpose: `Header` and `Paragraph` take their
text positionally, `Table` wraps `TableHelper.fromTextArray`, and `BulletList`
takes a whole list. Use `package:bangla_pdf/widgets.dart` when you want the
`pw` shapes instead — the two can be mixed in one file.

</details>

---

## 📥 Reading Bangla back out of a PDF

Point it at a PDF and get the text:

```dart
import 'package:bangla_pdf/extract.dart';

final result = BanglaPdfExtractor.extract(bytes);

print(result.text);
print(result.encodingDetected);   // unicode | bijoy | mixed | none
```

It also rescues **Bijoy** documents — the government and newspaper PDFs where
copying text gives you `Avgvi ‡mvbvi evsjv` instead of `আমার সোনার বাংলা`. Those
are detected and converted back for you.

Scanned pages report `BanglaTextEncoding.none` instead of guessing, and you can
plug in whichever OCR you already use:

```dart
BanglaPdfExtractor.extract(
  bytes,
  ocrHook: (page) => runTesseract(page.number, language: 'ben'),
);
```

It is a separate library, so generating PDFs costs nothing if you never import
it.

---

## 🔤 Want a different font?

```dart
final font = BanglaPdf.loadFont(
  await rootBundle.load('assets/fonts/SolaimanLipi.ttf'),
);

BanglaPdf.configure(defaultFont: font);   // everywhere
Text('বাংলা', banglaFont: font);          // or just here
```

SolaimanLipi, Siyam Rupali, Noto Sans Bengali and Noto Serif Bengali are all
tested. Your own Bijoy font keeps working too — it is detected and handled the
old way.

---

## ⬆️ Coming from bangla_pdf 1.0?

Nothing to change. `Text(...)`, `banglaStyle:`, `banglaFont:` and the
no-setup default all work as before, and the bundled typeface is still
Kalpurush — your documents look the same, the Bangla in them is just shaped
correctly now. The `package:bangla_pdf/widgets.dart` entry point above is
purely additive; you can adopt it file by file, or never.

<details>
<summary>What changed, in detail</summary>

- **Reph no longer crashes.** `কর্ম`, `ধর্ম`, `বর্ষ`, `পূর্ব`, `শর্ত` threw an
  uncaught `RangeError` in 1.0.6 that aborted `pdf.save()` outright. 21 of 253
  corpus cases crashed; none do now.
- **Conjuncts join.** `ক্ষ্ম`, `ঙ্ক্ষ`, `ত্ত্ব`, `চ্ছ্ব`, `ম্ভ্র`, `স্ত্র্য` used to render
  as a base plus a stray hasanta.
- **Digits and currency survive.** `০–৯` silently became `0–9`, and `৳` became `$`.
- **Copy, search and screen readers work.** The PDF now holds real Unicode
  instead of Bijoy ANSI.
- `ৰ` `ৱ` `॥` render instead of showing a missing-glyph box, and `র‍্য` is now
  distinguished from `র্য`.
- One font draws the whole string, so `style` and `banglaStyle` no longer give
  Bangla and Latin different looks inside one widget; `banglaStyle` wins when
  both are set. Use two widgets for two looks.
- `AutoText` and `RichTextItem` are **deprecated**. `Text` is identical to
  `AutoText` — splitting a string by script stopped being necessary once the
  Bangla font covered Latin and digits too — and `RichTextItem` was never used
  by anything. Both still work and are removed in 2.0.0.
- To get byte-identical 1.0.x output back, call
  `BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy)` once at startup.

</details>

---

## ✅ How well does it work?

Shaping is compared glyph by glyph against **HarfBuzz** — the engine behind
Chrome, Android and LibreOffice — over a 253-case corpus:

| font | exact match |
|---|---|
| Kalpurush *(bundled)* | **234 / 234** |
| SolaimanLipi | **234 / 234** |
| Siyam Rupali | **234 / 234** |
| Noto Sans Bengali | **234 / 234** |
| Noto Serif Bengali | **234 / 234** |

The text survives the round trip too: **249 of 251** cases come back out of a
generated PDF identical to what went in, checked with `pdftotext`. Extraction
recovers **8 of 8** fixture documents exactly and correctly reports both scanned
ones as having no text layer.

All of it runs on every commit — `flutter test` is 55 tests.

<details>
<summary>How the shaping actually works</summary>

Bangla is shaped with the font's own OpenType `GSUB`/`GPOS` tables, in **pure
Dart** — no FFI and no C toolchain, which is why this also works on Flutter web.

1. **Normalise** — NFC and NFD are reconciled, two-part vowels (`ো` `ৌ`) are
   split the way font rules expect, and nukta pairs are composed.
2. **Segment** the text into Indic syllables.
3. **Find the base consonant** by asking the font which consonants it gives
   below-base or post-base forms to.
4. **Reorder** — pre-base matras move in front of the cluster; reph moves after
   the base and any below-base form.
5. **Apply GSUB** in the OpenType Indic order — `nukt akhn rphf blwf half pstf
   vatu cjct`, then `pres abvs blws psts haln`, then `calt clig rclt rlig` —
   each under the right per-glyph mask. Both generations of the spec are
   handled: `bng2` fonts write their rules as *virama + consonant*, `beng` fonts
   the other way round.
6. **Apply GPOS** — `dist abvm blwm mark mkmk kern`, including mark-to-base,
   mark-to-ligature and mark-to-mark attachment.
7. **Emit** a `Type0`/`Identity-H` CID font addressed by glyph id, with an
   explicit `/CIDToGIDMap` and a `/ToUnicode` CMap whose entries may span
   several codepoints — so a conjunct copies back as its full sequence.
8. **Wrap each line** in a `/Span <</ActualText …>> BDC … EMC` marked-content
   span. This is what makes copy/paste survive Bengali's glyph reordering: `কি`
   draws `ি` first, so no per-glyph mapping alone can express logical order.

Lines break on syllable boundaries, so a line never splits inside a conjunct or
between a vowel sign and its consonant.

Full write-ups live in the repository: the [verification report][report] and the
[1.0.6 teardown][teardown].

</details>

---

## ⚠️ Known limitations

- **Extraction cannot rescue every third-party PDF.** A document with no
  `/ToUnicode` and no `/ActualText` cannot be recovered — that needs reversing
  the shaping from glyph ids back to characters, which is not implemented.
- **Encrypted PDFs are not decrypted.** `ExtractionResult.isEncrypted` says so
  rather than returning nonsense.
- **Emoji need a fallback font.** The bundled font covers ASCII, Bengali and
  common punctuation; emoji render as a placeholder box.
- **The full font is embedded in every PDF** (121 KB) — there is no per-document
  subsetter yet.
- **Five fonts are measured.** Others should work but are untested. A font
  relying on GSUB lookup type 8 or GPOS type 3 would not shape; no Bengali font
  tested uses either.
- **Form fields shape only their appearance.** `pw.TextField` and
  `pw.ChoiceField` draw a shaped value, but once a reader lets someone edit the
  field it re-renders from the form font. No PDF producer controls that.
- **Rendering is not pixel-diffed**, and copy/paste is verified with poppler
  only — not Adobe Reader, Preview or Chrome.
- **Extraction fixtures are generated, not collected** — shaped like real
  notices, invoices and newspaper pages, but not downloaded from a government
  website.

---

## 🤝 Contributing

Found Bangla that renders wrong? That is the most useful bug report there is.
Add the string to [`test/corpus/bangla_cases.json`][corpus] with an `id`,
`category` and `notes`, and the differential harness picks it up.

```bash
flutter test                                  # unit and PDF-structure tests
dart run tool/dev/shape_dump.dart <font.ttf>  # diff against hb-shape
```

`hb-shape` (`brew install harfbuzz`) and `pdftotext` (`brew install poppler`)
are needed for the verification tooling, not for the package itself.

---

## 📄 License

BSD 3-Clause — see [LICENSE](LICENSE).

The bundled **Kalpurush** is by Md. Tanbin Islam Siyam (Avro Font Development
Project, [omicronlab.com](https://www.omicronlab.com)) under the SIL Open Font
License 1.0; its Latin glyphs are from Gentium. Font licences are in
[LICENSE-FONTS.txt](LICENSE-FONTS.txt).

---

## 💛 Credits

Maintained by **[Zaman Sheikh](https://github.com/zamansheikh)** ·
[zaman6545@gmail.com](mailto:zaman6545@gmail.com)

The legacy Bijoy pipeline kept for backward compatibility
(`BanglaShapingMode.legacy`) descends from the ANSI transcoding approach in
**AR Rahman**'s [bangla_pdf_fixer](https://pub.dev/packages/bangla_pdf_fixer)
2.x. It is retained only so 1.0.x users can reproduce their old output; the
shaping in this package does not use it.

Thanks to every Bangla font creator whose work makes readable Bangla typography
possible.

⭐ If this saved you a day of debugging, star the repo.

[report]: https://github.com/zamansheikh/bangla_pdf/blob/main/docs/VERIFICATION_REPORT.md
[teardown]: https://github.com/zamansheikh/bangla_pdf/blob/main/docs/CURRENT_STATE.md
[corpus]: https://github.com/zamansheikh/bangla_pdf/blob/main/test/corpus/bangla_cases.json
