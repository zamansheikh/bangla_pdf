# Bangla PDF 🔧

[![Stand With Palestine](https://github.com/zamansheikh/bangla_pdf/raw/main/images/StandWithPalestine.svg)](https://pub.dev/packages/bangla_pdf)

**Bangla PDF** renders correct Bangla in PDFs — real OpenType shaping, and text
that copies back out as clean Unicode.

A lightweight, focused solution for Bangla in PDFs—**nothing more, nothing less**.

---

## What changed in 1.1.0

Up to 1.0.6 this package transcoded Unicode to **Bijoy ANSI** and drew it with a
legacy 8-bit font. That worked for ordinary prose, but conjuncts outside a
hand-written table broke, reph words *crashed*, and the PDF contained no Bengali
at all — copy/paste gave you `Avgvi ‡mvbvi evsjv`.

1.1.0 shapes Bangla with the font's own GSUB/GPOS tables, in pure Dart.

| | 1.0.6 | 1.1.0 |
|---|---|---|
| `কর্ম` `ধর্ম` `বর্ষ` `পূর্ব` `শর্ত` | **throws `RangeError`, kills `pdf.save()`** | renders correctly |
| corpus cases that crash | **21 / 253** | **0 / 253** |
| `ক্ষ্ম` `ঙ্ক্ষ` `ত্ত্ব` `চ্ছ্ব` `ম্ভ্র` `স্ত্র্য` | base + a stray hasanta `্` | ligated |
| shaping vs HarfBuzz | not a shaper | **234 / 234 exact (100%)**, on all 3 test fonts |
| copy/paste, search, `pdftotext` | **mojibake (0%)** | **249 / 251 exact (99%)** |
| Bengali digits `০–৯` | silently became `0–9` | preserved |
| `৳` | silently became `$` | preserved |
| `ৰ` `ৱ` `॥` | missing glyph | rendered |
| NFC vs NFD input | mostly equivalent | identical |
| `র‍্য` vs `র্য` (ZWJ) | ZWJ discarded | distinguished |

Full evidence: [docs/VERIFICATION_REPORT.md](docs/VERIFICATION_REPORT.md).
How 1.0.6 worked and why: [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md).

### Migration for 1.x users — three lines

1. Nothing to change. `Text(...)`, `banglaStyle:`, `banglaFont:` and
   no-initialisation-needed all work as before.
2. The typeface does not change: the bundled font is still **Kalpurush**, now
   the Unicode build instead of the 8-bit Bijoy one. Documents look the same;
   what changes is that the Bangla in them is shaped correctly.
3. If you pass your own **Bijoy/ANSI** font to `banglaFont:`, it is detected and
   keeps the old pipeline automatically — no change needed. To force the old
   output everywhere, call
   `BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy)` once at startup.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  bangla_pdf: ^1.1.0
```

```bash
flutter pub get
```

---

## Usage ✨

### The Magic 🪄 (Auto Mixed Text)

```dart
// No initialisation. Bangla is shaped, Latin and digits just work.
Text('আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।');

Text(
  'Hello বাংলাদেশ world! ৳১২,৫০০.০০',
  style: pw.TextStyle(fontSize: 25, color: PdfColors.blue),
);
```

### Using your own Unicode Bangla font

```dart
final font = BanglaPdf.loadFont(
  await rootBundle.load('assets/SolaimanLipi.ttf'),
);

Text('বাংলা', banglaFont: font);
// or set it once for everything:
BanglaPdf.configure(defaultFont: font);
```

`BanglaPdf.loadFont` returns a font that shapes with its own OpenType tables.
A plain `pw.Font.ttf` still works, but is treated as a legacy 8-bit font.

### Choosing a shaping mode

```dart
BanglaPdf.configure(shapingMode: BanglaShapingMode.auto);    // default
BanglaPdf.configure(shapingMode: BanglaShapingMode.unicode); // always shape
BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy);  // 1.0.x Bijoy output
```

---

## Example: Generate a PDF

```dart
import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';

Future<void> generateAndOpenPdf() async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          Text(
            'This is a mixed text: আমি বাংলাদেশ ভালোবাসি। I love Bangladesh.',
            style: pw.TextStyle(fontSize: 20),
          ),
        ],
      ),
    ),
  );

  final dir = await getApplicationDocumentsDirectory();
  final file = File("${dir.path}/example.pdf");
  await file.writeAsBytes(await pdf.save());
  await OpenFile.open(file.path);
}
```

---

## Other Widgets (Optional)

* **Table**: mixed language in cells.
* **BulletList**: bullet points.
* **Header**, **Paragraph**, **RichText**.

```dart
Table(data: [
  ['Name', 'Country'],
  ['Zaman', 'বাংলাদেশ'],
]);

BulletList(items: ['First Item', 'দ্বিতীয় আইটেম', 'Third Item']);
```

---

## Known limitations

Stated plainly rather than glossed over.

* **Only three fonts are measured.** Bundled Kalpurush, Noto Sans Bengali and
  Noto Serif Bengali all match HarfBuzz on every corpus case. SolaimanLipi,
  Siyam Rupali and others are untested. A font relying on GSUB lookup type 8
  (reverse chaining) or GPOS type 3 (cursive attachment) would not shape —
  neither is implemented, because no tested Bengali font uses them.
* **Rendering is not pixel-diffed.** Output was rasterised and compared against
  HarfBuzz reference renders by eye for a sample, not automatically for all 253
  cases.
* **Copy/paste is verified with poppler only.** Adobe Reader, macOS Preview,
  Chrome and Android viewers have not been tested. `/ActualText` support varies.
* **The full font is embedded in every PDF** (121 KB); there is no per-document
  subsetter yet.
* **Emoji need a fallback font.** The bundled font covers ASCII, the Bengali
  block and common punctuation. Emoji still render as a placeholder box, and
  `BulletList` falls back from `•` to `·` because Kalpurush has no bullet.
* **PDF text extraction is not implemented.** There is no
  `package:bangla_pdf/extract.dart` yet — no Bijoy→Unicode reverse mapping and
  no scanned-PDF handling.
* **No HarfBuzz companion.** Shaping is pure Dart, so it works on every
  platform including web, but `BanglaShapingMode.harfbuzz` does not exist.

---

## Contributing 🚀

Contributions are welcome! Whether you want to:

* Report a bug
* Suggest a feature
* Improve widgets or documentation

**Fork the repository, make changes, and submit a Pull Request**. Together, we can enhance Bangla PDF! 💡

---

## License

This project is licensed under the **BSD 3-Clause License**.
Read the full license [here](https://github.com/zamansheikh/bangla_pdf/blob/main/LICENSE).

The bundled Kalpurush is by Md. Tanbin Islam Siyam (Avro Font Development
Project) under the SIL Open Font License 1.0; see
[LICENSE-FONTS.txt](LICENSE-FONTS.txt).

---

## Author

Maintained by **Zaman Sheikh**
Contact: [zaman6545@gmail.com](mailto:zaman6545@gmail.com)

---

## Inspiration & Credit 💡

This package is inspired by the work of **AR Rahman** and his package [bangla_pdf_fixer](https://pub.dev/packages/bangla_pdf_fixer).
We acknowledge his contribution to the community in solving Bangla font rendering issues in PDFs.

---

## Special Thanks 🙏✨

A big thank you to all **Bangla font creators and contributors**. Your efforts make **high-quality, beautiful Bangla PDFs** possible. 💖

---

⭐ If you find Bangla PDF helpful, please **star the repository**!
