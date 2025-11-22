
# Bangla PDF 🔧

[![Stand With Palestine](https://github.com/zamansheikh/bangla_pdf/raw/main/images/StandWithPalestine.svg)](https://pub.dev/packages/bangla_pdf)

**Bangla PDF** is a Flutter package designed to **fix broken Bangla fonts in PDFs**, ensuring accurate rendering of Bangla characters.

A lightweight, focused solution for Bangla font issues—**nothing more, nothing less**.

---

## Features

* **Auto-detects & Renders** mixed Bangla and English text seamlessly.
* **Built-in Kalpurush font** for beautiful Bangla typography.
* **Support for Custom Fonts** - Use any Bangla font you like!
* **No manual fixes needed** – just use the `Text` widget.
* **Ready-to-use widgets** for tables, lists, and more.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  bangla_pdf: ^1.0.3
```

Install packages:

```bash
flutter pub get
```

---

## Usage ✨

### The Magic 🪄 (Auto Mixed Text)

The easiest way to use this package is with the `Text` widget. It automatically detects Bangla and English parts and applies the correct fonts.

```dart
// Simple usage (Uses default Kalpurush font - No initialization needed!)
Text('Hello 🐒💁👌🎍😍🦊👨বাংলাদেশ world!');

// With custom styling (For custom fonts, pass the font object)
final myFont = pw.Font.ttf(await rootBundle.load('assets/my_font.ttf'));

Text(
  'Hello 🐒💁👌🎍😍🦊👨বাংলাদেশ world!',
  style: pw.TextStyle(
    fontSize: 25,
    color: PdfColors.blue,
  ),
  banglaStyle: pw.TextStyle(
    font: myFont,
    fontSize: 24,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.red,
  ),
);
```

This works exactly like a native widget but handles the complex font switching for you! 

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
          // Just use Text() for everything!
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

If you need specific widgets, we have them too:

* **Table**: Supports mixed language in cells automatically.
* **BulletList**: For bullet points (supports mixed text).
* **Header**: For bold headers.

```dart
// Table Example
Table(
  data: [
    ['Name', 'Country'],
    ['Zaman', 'বাংলাদেশ'],
  ],
);

// Bullet List Example
BulletList(
  items: ['First Item', 'দ্বিতীয় আইটেম', 'Third Item'],
);
```

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