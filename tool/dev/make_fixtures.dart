// Builds the real-world-shaped fixture PDFs used to test extraction, together
// with a ground-truth file for each.
//
// They are generated rather than collected so the expected text is known
// exactly. The Bijoy ones go through the 1.0.x ANSI pipeline with a real
// legacy font, so their text layer is genuine Bijoy mojibake — the same thing
// a government PDF produced in Bijoy contains.
//
//   dart run tool/dev/make_fixtures.dart   (via test/_fixtures_test.dart)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A fixture: the document to build and the text it must extract back to.
class Fixture {
  Fixture({
    required this.name,
    required this.kind,
    required this.lines,
    this.bijoy = false,
    this.scanned = false,
  });

  final String name;
  final String kind;
  final List<String> lines;
  final bool bijoy;
  final bool scanned;
}

final fixtures = <Fixture>[
  Fixture(
    name: 'gov-notice-1',
    kind: 'Bijoy government notice',
    bijoy: true,
    lines: <String>[
      'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার',
      'স্থানীয় সরকার বিভাগ',
      'স্মারক নং ৪৬.০০.০০০০.০১৪.৯৯.০০১.২৬',
      'বিষয়: জন্ম নিবন্ধন সনদ প্রাপ্তির আবেদন প্রসঙ্গে।',
      'উপর্যুক্ত বিষয়ে জানানো যাচ্ছে যে, নির্ধারিত ফরম পূরণ করে',
      'সংশ্লিষ্ট কার্যালয়ে জমা দিতে হবে।',
      'স্বাক্ষরিত',
      'উপসচিব',
    ],
  ),
  Fixture(
    name: 'gov-notice-2',
    kind: 'Bijoy government notice',
    bijoy: true,
    lines: <String>[
      'শিক্ষা মন্ত্রণালয়',
      'মাধ্যমিক ও উচ্চশিক্ষা অধিদপ্তর',
      'পরিপত্র',
      'সকল সরকারি ও বেসরকারি শিক্ষা প্রতিষ্ঠানের প্রধানগণকে জানানো যাচ্ছে,',
      'আগামী শিক্ষাবর্ষের ভর্তি কার্যক্রম অনলাইনে সম্পন্ন হবে।',
      'কর্তৃপক্ষের নির্দেশক্রমে জারি করা হলো।',
    ],
  ),
  Fixture(
    name: 'gov-notice-3',
    kind: 'Bijoy government notice',
    bijoy: true,
    lines: <String>[
      'ভূমি মন্ত্রণালয়',
      'বিজ্ঞপ্তি',
      'ভূমি উন্নয়ন কর পরিশোধের সময়সীমা বর্ধিত করা হয়েছে।',
      'নির্ধারিত তারিখের মধ্যে কর পরিশোধ না করিলে',
      'আইনানুগ ব্যবস্থা গ্রহণ করা হইবে।',
      'তারিখ: ০১/০৯/২০২৬',
    ],
  ),
  Fixture(
    name: 'invoice-1',
    kind: 'Unicode invoice',
    lines: <String>[
      'চালান',
      'বিক্রেতা: সিলিফটন টেকনোলজিস লিমিটেড',
      'ক্রেতা: মোহাম্মদ রফিকুল ইসলাম',
      'বিবরণ: কম্পিউটার যন্ত্রাংশ',
      'পরিমাণ: ৩ — একক মূল্য: ৳১২,৫০০.০০',
      'মোট: ৳৩৭,৫০০.০০',
      'তারিখ: ০১/০৯/২০২৬',
    ],
  ),
  Fixture(
    name: 'invoice-2',
    kind: 'Unicode invoice',
    lines: <String>[
      'ট্যাক্স ইনভয়েস',
      'প্রতিষ্ঠান: ঢাকা ট্রেডার্স',
      'পণ্য: চাল, ডাল, তেল',
      'পরিমাণ: ১০ কেজি',
      'মূল্য: ৳৮,৭৫০.৫০',
      'ভ্যাট (১৫%): ৳১,৩১২.৫৮',
      'সর্বমোট: ৳১০,০৬৩.০৮',
    ],
  ),
  Fixture(
    name: 'invoice-3',
    kind: 'Unicode invoice, mixed script',
    lines: <String>[
      'INVOICE #2026-0912',
      'গ্রাহক: Rahim Enterprise',
      'Item: Laptop — পরিমাণ ২',
      'Unit price: ৳৮৫,০০০.০০',
      'Total: ৳১,৭০,০০০.০০',
      'Payment: bKash / নগদ',
    ],
  ),
  Fixture(
    name: 'newspaper-1',
    kind: 'Unicode newspaper page',
    lines: <String>[
      'দৈনিক সংবাদ',
      'ঢাকা বিশ্ববিদ্যালয়ে সমাবেশ',
      'ঢাকা বিশ্ববিদ্যালয়ের শিক্ষার্থীরা গতকাল কেন্দ্রীয় শহীদ মিনারে',
      'সমাবেশ করেছেন। সমাবেশে বক্তারা শিক্ষা ব্যবস্থার সংস্কারের',
      'দাবি জানান। কর্তৃপক্ষ বিষয়টি বিবেচনার আশ্বাস দিয়েছে।',
      'আবহাওয়া অধিদপ্তর জানিয়েছে, আগামী ২৪ ঘণ্টায় বৃষ্টিপাতের',
      'সম্ভাবনা রয়েছে।',
    ],
  ),
  Fixture(
    name: 'newspaper-2',
    kind: 'Bijoy newspaper page',
    bijoy: true,
    lines: <String>[
      'প্রথম পাতা',
      'অর্থনীতি: রপ্তানি আয় বৃদ্ধি',
      'গত অর্থবছরে তৈরি পোশাক খাতে রপ্তানি আয় উল্লেখযোগ্যভাবে',
      'বৃদ্ধি পেয়েছে বলে জানিয়েছে রপ্তানি উন্নয়ন ব্যুরো।',
      'বিশ্লেষকরা মনে করছেন, এই ধারা অব্যাহত থাকবে।',
      'ক্রীড়া: বাংলাদেশের জয়',
    ],
  ),
  Fixture(
    name: 'scan-1',
    kind: 'Scanned page, no text layer',
    scanned: true,
    lines: <String>[
      'এই পৃষ্ঠাটি স্ক্যান করা হয়েছে।',
      'কোনো টেক্সট স্তর নেই।',
    ],
  ),
  Fixture(
    name: 'scan-2',
    kind: 'Scanned page, no text layer',
    scanned: true,
    lines: <String>[
      'দ্বিতীয় স্ক্যান করা পৃষ্ঠা।',
      'শুধুমাত্র ছবি রয়েছে।',
    ],
  ),
];

/// Builds every fixture into [directory].
///
/// [rasterise] converts a one-page PDF to PNG bytes; it is how the scanned
/// fixtures get built, and is supplied by the caller so this file stays free of
/// external tooling.
Future<void> buildFixtures(
  String directory, {
  required Future<Uint8List?> Function(Uint8List pdf) rasterise,
}) async {
  Directory(directory).createSync(recursive: true);
  final manifest = <Map<String, dynamic>>[];

  for (final fixture in fixtures) {
    BanglaPdf.reset();
    final legacyFont = fixture.bijoy ? BanglaFontManager().legacyFont : null;

    Uint8List bytes;
    if (fixture.scanned) {
      // Render the text, rasterise it, then wrap the image in a fresh PDF so
      // the result has pixels and no text layer at all.
      final source = await _textDocument(fixture, null).save();
      final png = await rasterise(source);
      bytes = png == null ? source : await _imageDocument(png).save();
    } else {
      bytes = await _textDocument(fixture, legacyFont).save();
    }

    File('$directory/${fixture.name}.pdf').writeAsBytesSync(bytes);
    manifest.add(<String, dynamic>{
      'name': fixture.name,
      'kind': fixture.kind,
      'encoding':
          fixture.scanned ? 'none' : (fixture.bijoy ? 'bijoy' : 'unicode'),
      // A scan has no text layer at all, so nothing is extractable from it and
      // these lines are only what an OCR hook would have to recover.
      'extractable': !fixture.scanned,
      'lines': fixture.lines,
    });
  }

  BanglaPdf.reset();
  File('$directory/ground_truth.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(manifest),
  );
}

pw.Document _textDocument(Fixture fixture, pw.Font? banglaFont) {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          for (final line in fixture.lines) ...<pw.Widget>[
            Text(line, fontSize: 13, banglaFont: banglaFont),
            pw.SizedBox(height: 4),
          ],
        ],
      ),
    ),
  );
  return pdf;
}

pw.Document _imageDocument(Uint8List png) {
  final pdf = pw.Document();
  final image = pw.MemoryImage(png);
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(child: pw.Image(image)),
    ),
  );
  return pdf;
}
