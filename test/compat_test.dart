// Exercises `package:bangla_pdf/widgets.dart` as what it claims to be: a
// replacement for `package:pdf/widgets.dart` that needs no other edit.
//
// Note the import below — this file deliberately never imports
// `package:pdf/widgets.dart`, so anything it uses has to come through our
// re-export. If the `hide` list drops a symbol, or a replacement's signature
// drifts from its `pw` counterpart, this file stops compiling.
// The parity group passes defaults on purpose -- that is what it is checking.
// ignore_for_file: avoid_redundant_argument_values, prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart' show BanglaPdf, BanglaShapingMode;
// The original API's Text, for comparing the drop-in's layout against it.
import 'package:bangla_pdf/bangla_pdf.dart' as bp show Text;
import 'package:bangla_pdf/extract.dart';
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as native;

String flatten(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

/// Whether the file contains an `/ActualText` span, which only the shaped path
/// emits. It is how these tests tell which path a string took.
bool wasShaped(Uint8List bytes) =>
    latin1.decode(bytes, allowInvalid: true).contains('/ActualText');

Future<Uint8List> page(pw.Widget child) {
  final pdf = pw.Document(compress: false);
  pdf.addPage(pw.Page(build: (context) => child));
  return pdf.save();
}

Future<Uint8List> nativePage(native.Widget child) {
  final pdf = native.Document(compress: false);
  pdf.addPage(native.Page(build: (context) => child));
  return pdf.save();
}

void main() {
  tearDown(BanglaPdf.reset);

  group('the import swap is the whole migration', () {
    test('pw.Text shapes Bangla and comes back out intact', () async {
      const line = 'আমার সোনার বাংলা, ক্ষ্ম কর্ম ৳১২,৫০০.০০';
      final bytes = await page(pw.Text(line));

      expect(wasShaped(bytes), isTrue);
      expect(flatten(BanglaPdfExtractor.extract(bytes).text), flatten(line));
    });

    test('a document with no Bangla stays on the package:pdf path', () async {
      const line = 'Invoice #1042 — total 12,500.00 — 01/09/2026';
      final ours = await page(pw.Text(line));
      final theirs = await nativePage(native.Text(line));

      // Nothing was shaped, so the page content is what package:pdf produces.
      expect(wasShaped(ours), isFalse);
      expect(
        flatten(BanglaPdfExtractor.extract(ours).text),
        flatten(BanglaPdfExtractor.extract(theirs).text),
      );
    });

    test('every replaced widget renders Bangla correctly', () async {
      final pdf = pw.Document(compress: false);
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Header(level: 1, text: 'গণপ্রজাতন্ত্রী বাংলাদেশ'),
              pw.Paragraph(text: 'একটি অনুচ্ছেদ যেখানে ক্ষ্ম আছে।'),
              pw.Bullet(text: 'প্রথম আইটেম'),
              pw.RichText(
                text: pw.TextSpan(
                  children: <pw.InlineSpan>[
                    pw.TextSpan(text: 'বাংলা '),
                    pw.TextSpan(
                      text: 'বোল্ড',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.TableHelper.fromTextArray(
                headers: <String>['পণ্য', 'মূল্য'],
                data: <List<String>>[
                  <String>['কফি', '৳২০'],
                ],
              ),
            ],
          ),
        ),
      );

      final bytes = await pdf.save();
      final text = BanglaPdfExtractor.extract(bytes).text;
      for (final expected in <String>[
        'গণপ্রজাতন্ত্রী বাংলাদেশ',
        'একটি অনুচ্ছেদ যেখানে ক্ষ্ম আছে।',
        'প্রথম আইটেম',
        'বাংলা',
        'বোল্ড',
        'পণ্য',
        'কফি',
        '৳২০',
      ]) {
        expect(flatten(text), contains(expected));
      }
    });

    test('a Bangla watermark, legend and axis label all shape', () async {
      final watermark = await page(
        pw.Stack(
          children: <pw.Widget>[
            pw.Text('দলিল'),
            pw.Watermark.text('গোপনীয়'),
          ],
        ),
      );
      expect(wasShaped(watermark), isTrue);

      final chart = await page(
        pw.SizedBox(
          width: 300,
          height: 200,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis.fromStrings(<String>['জানু', 'ফেব্রু']),
              yAxis: pw.FixedAxis<int>(<int>[0, 5, 10]),
            ),
            overlay: pw.ChartLegend(),
            datasets: <pw.Dataset>[
              pw.BarDataSet(
                legend: 'বিক্রয়',
                data: const <pw.PointChartValue>[
                  pw.PointChartValue(0, 5),
                  pw.PointChartValue(1, 8),
                ],
              ),
            ],
          ),
        ),
      );
      expect(wasShaped(chart), isTrue);
      final text = flatten(BanglaPdfExtractor.extract(chart).text);
      expect(text, contains('বিক্রয়'));
      expect(text, contains('জানু'));
    });

    test('a form field draws its Bangla value in the appearance', () async {
      final bytes = await page(
        pw.Column(
          children: <pw.Widget>[
            pw.TextField(name: 'naam', value: 'রফিকুল ইসলাম'),
            pw.ChoiceField(
              name: 'jela',
              items: const <String>['ঢাকা', 'চট্টগ্রাম'],
              value: 'ঢাকা',
            ),
          ],
        ),
      );
      expect(wasShaped(bytes), isTrue);
    });

    test('a table of contents shapes its Bangla headings', () async {
      final pdf = pw.Document(compress: false);
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            children: <pw.Widget>[
              pw.Header(level: 1, text: 'প্রথম অধ্যায়'),
              pw.TableOfContent(),
            ],
          ),
        ),
      );
      expect(wasShaped(await pdf.save()), isTrue);
    });
  });

  group('signature parity', () {
    test('the replacements take every parameter pw does', () async {
      // This body is a compile-time assertion: it passes every parameter each
      // pw counterpart declares. A dropped or renamed one fails the build.
      final bytes = await page(
        pw.Column(
          children: <pw.Widget>[
            pw.Text(
              'বাংলা',
              style: const pw.TextStyle(fontSize: 12),
              textAlign: pw.TextAlign.left,
              textDirection: pw.TextDirection.ltr,
              softWrap: true,
              tightBounds: false,
              textScaleFactor: 1,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
            ),
            pw.RichText(
              text: const pw.TextSpan(
                text: 'বাংলা',
                style: pw.TextStyle(fontSize: 12),
                baseline: 0,
                children: <pw.InlineSpan>[],
              ),
              textAlign: pw.TextAlign.left,
              textDirection: pw.TextDirection.ltr,
              softWrap: true,
              tightBounds: false,
              textScaleFactor: 1,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
              hyphenation: (w) => <String>[w],
            ),
            pw.Header(
              level: 2,
              text: 'শিরোনাম',
              title: 'শিরোনাম',
              decoration: const pw.BoxDecoration(),
              margin: const pw.EdgeInsets.all(1),
              padding: const pw.EdgeInsets.all(1),
              textStyle: const pw.TextStyle(fontSize: 14),
              outlineColor: PdfColors.black,
              outlineStyle: PdfOutlineStyle.normal,
            ),
            pw.Paragraph(
              text: 'অনুচ্ছেদ',
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(fontSize: 11),
              margin: const pw.EdgeInsets.all(1),
              padding: const pw.EdgeInsets.all(1),
            ),
            pw.Bullet(
              text: 'আইটেম',
              textAlign: pw.TextAlign.left,
              style: const pw.TextStyle(fontSize: 11),
              margin: const pw.EdgeInsets.all(1),
              padding: const pw.EdgeInsets.all(1),
              bulletSize: 3,
              bulletMargin: const pw.EdgeInsets.all(2),
              bulletShape: pw.BoxShape.circle,
              bulletColor: PdfColors.black,
            ),
            pw.TableHelper.fromTextArray(
              data: <List<String>>[
                <String>['কফি', '২'],
              ],
              headers: <String>['পণ্য', 'সংখ্যা'],
              cellPadding: const pw.EdgeInsets.all(4),
              cellHeight: 12,
              cellAlignment: pw.Alignment.topLeft,
              cellAlignments: const <int, pw.Alignment>{},
              cellStyle: const pw.TextStyle(fontSize: 10),
              oddCellStyle: const pw.TextStyle(fontSize: 10),
              cellFormat: (i, d) => d.toString(),
              cellDecoration: (i, d, r) => const pw.BoxDecoration(),
              headerCount: 1,
              headerPadding: const pw.EdgeInsets.all(4),
              headerHeight: 14,
              headerAlignment: pw.Alignment.center,
              headerAlignments: const <int, pw.Alignment>{},
              headerStyle: const pw.TextStyle(fontSize: 11),
              headerFormat: (i, d) => d.toString(),
              columnWidths: const <int, pw.TableColumnWidth>{},
              defaultColumnWidth: const pw.IntrinsicColumnWidth(),
              tableWidth: pw.TableWidth.max,
              headerDecoration: const pw.BoxDecoration(),
              headerCellDecoration: const pw.BoxDecoration(),
              rowDecoration: const pw.BoxDecoration(),
              oddRowDecoration: const pw.BoxDecoration(),
              headerDirection: pw.TextDirection.ltr,
              tableDirection: pw.TextDirection.ltr,
              cellBuilder: (i, d, r) => null,
              textStyleBuilder: (i, d, r) => null,
            ),
          ],
        ),
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('layout', () {
    test('a shaped widget reports a real height', () async {
      // pw's TextStyle.lineSpacing is extra leading in points and defaults to
      // 0, while ShapedTextWidget's is a multiplier. Feeding one into the
      // other collapsed every compat widget to zero height, so any Column or
      // Container around one laid out wrongly while still painting its text.
      final compat = pw.Text(
        '৳৩৮৩ কোটি',
        style: const pw.TextStyle(fontSize: 15),
      );
      final legacyApi = bp.Text('৳৩৮৩ কোটি', fontSize: 15);

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[compat, legacyApi],
          ),
        ),
      );
      await pdf.save();

      expect(compat.box!.height, greaterThan(0));
      // The drop-in must lay out identically to the original API.
      expect(compat.box!.height, closeTo(legacyApi.box!.height, 0.001));
      expect(compat.box!.width, closeTo(legacyApi.box!.width, 0.001));
    });

    test('explicit lineSpacing adds leading, as it does in package:pdf',
        () async {
      final tight = pw.Text('বাংলা', style: const pw.TextStyle(fontSize: 12));
      final loose = pw.Text(
        'বাংলা',
        style: const pw.TextStyle(fontSize: 12, lineSpacing: 8),
      );
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(children: <pw.Widget>[tight, loose]),
        ),
      );
      await pdf.save();
      expect(loose.box!.height, closeTo(tight.box!.height + 8, 0.001));
    });
  });

  group('spanning pages', () {
    const paragraph =
        'গণপ্রজাতন্ত্রী বাংলাদেশ সরকারের স্থানীয় সরকার বিভাগ কর্তৃক জারিকৃত '
        'এই পরিপত্রে বলা হয়েছে যে, নির্ধারিত ফরম পূরণ করে সংশ্লিষ্ট কার্যালয়ে '
        'জমা দিতে হবে এবং কর্তৃপক্ষের নির্দেশক্রমে বিষয়টি নিষ্পত্তি করা হবে। ';

    Future<Uint8List> multiPage(String text, pw.TextOverflow overflow) {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: const PdfPageFormat(400, 260, marginAll: 20),
          build: (context) => <pw.Widget>[pw.Text(text, overflow: overflow)],
        ),
      );
      return pdf.save();
    }

    test('a long Bangla paragraph breaks across pages', () async {
      final source = paragraph * 12;
      final result = BanglaPdfExtractor.extract(
        await multiPage(source, pw.TextOverflow.span),
      );

      // Several pages, and every word survives in order exactly once: no line
      // dropped at a page break and none repeated.
      expect(result.pages.length, greaterThan(2));
      expect(flatten(result.text), flatten(source));
    });

    test('without overflow: span it behaves as package:pdf does', () async {
      // pw.RichText spans only when its overflow is `span`; anything taller
      // than the page otherwise fails, for Bangla and Latin alike. The point
      // is that both scripts behave the same way, not that either succeeds.
      Future<Object?> failure(Future<void> Function() body) async {
        try {
          await body();
          return null;
        } catch (error) {
          return error;
        }
      }

      final bangla = await failure(
        () => multiPage(paragraph * 12, pw.TextOverflow.visible),
      );
      final latin = await failure(() async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.MultiPage(
            pageFormat: const PdfPageFormat(400, 260, marginAll: 20),
            build: (context) => <pw.Widget>[
              pw.Text('The quick brown fox jumps over it. ' * 60),
            ],
          ),
        );
        await pdf.save();
      });

      expect(bangla, isNotNull, reason: 'Bangla should overflow like Latin');
      expect(latin, isNotNull, reason: 'package:pdf itself refuses this');
    });

    test('a short paragraph is unaffected by being spannable', () async {
      final result = BanglaPdfExtractor.extract(
        await multiPage(paragraph, pw.TextOverflow.span),
      );
      expect(result.pages.length, 1);
      expect(flatten(result.text), flatten(paragraph));
    });
  });

  group('alignment', () {
    const sentence =
        'গণপ্রজাতন্ত্রী বাংলাদেশ সরকারের স্থানীয় সরকার বিভাগ কর্তৃক জারিকৃত এই '
        'পরিপত্রে বলা হয়েছে যে, নির্ধারিত ফরম পূরণ করে সংশ্লিষ্ট কার্যালয়ে জমা '
        'দিতে হবে এবং কর্তৃপক্ষের নির্দেশক্রমে বিষয়টি নিষ্পত্তি করা হবে।';

    Future<Uint8List> aligned(pw.TextAlign align) {
      final pdf = pw.Document(compress: false);
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(360, 300, marginAll: 24),
          build: (context) => pw.Text(
            sentence,
            textAlign: align,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      );
      return pdf.save();
    }

    test('justify spreads the slack instead of falling back to left', () async {
      // Justification is applied by shifting glyphs, so the give-away is that
      // the content stream differs from the ragged one.
      final justified = await aligned(pw.TextAlign.justify);
      final ragged = await aligned(pw.TextAlign.start);
      expect(
        latin1.decode(justified, allowInvalid: true),
        isNot(latin1.decode(ragged, allowInvalid: true)),
        reason: 'justify produced the same output as start',
      );
    });

    test('justifying does not disturb the text that comes back out', () async {
      final justified = BanglaPdfExtractor.extract(
        await aligned(pw.TextAlign.justify),
      );
      final ragged = BanglaPdfExtractor.extract(
        await aligned(pw.TextAlign.start),
      );
      expect(flatten(justified.text), flatten(sentence));
      expect(flatten(justified.text), flatten(ragged.text));
    });
  });

  group('choosing a font', () {
    pw.Font fixture(String name) => pw.Font.ttf(
          File('test/fixtures/fonts/$name')
              .readAsBytesSync()
              .buffer
              .asByteData(),
        );

    /// The PostScript names of the fonts embedded in [bytes].
    Set<String> embedded(Uint8List bytes) =>
        RegExp(r'/BaseFont\s*/([A-Za-z0-9+\-]+)')
            .allMatches(latin1.decode(bytes, allowInvalid: true))
            .map((m) => m.group(1)!)
            .toSet();

    Future<Uint8List> styled(pw.Font? font) => page(
          pw.Text(
            'আমার বাংলা',
            style: font == null ? null : pw.TextStyle(font: font),
          ),
        );

    test('a font from BanglaPdf.loadFont shapes with itself', () async {
      final font = BanglaPdf.loadFont(
        File('test/fixtures/fonts/NotoSansBengali-Regular.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      );
      final bytes = await styled(font);
      expect(wasShaped(bytes), isTrue);
      expect(embedded(bytes).single, contains('NotoSansBengali'));
    });

    test('BanglaPdf.configure(defaultFont:) applies to every widget', () async {
      // A plain pw.Font.ttf is accepted here as well as one from loadFont:
      // configure() upgrades it when it covers Bengali.
      for (final font in <pw.Font>[
        fixture('SolaimanLipi.ttf'),
        BanglaPdf.loadFont(
          File('test/fixtures/fonts/SolaimanLipi.ttf')
              .readAsBytesSync()
              .buffer
              .asByteData(),
        )!,
      ]) {
        BanglaPdf.reset();
        BanglaPdf.configure(defaultFont: font);
        final bytes = await styled(null);
        expect(wasShaped(bytes), isTrue);
        expect(embedded(bytes).single, contains('SolaimanLipi'));
      }
    });

    test('configure() with a Bijoy font keeps the legacy pipeline', () async {
      BanglaPdf.configure(defaultFont: fixture('Kalpurush-ANSI.ttf'));
      final bytes = await styled(null);
      expect(wasShaped(bytes), isFalse);
      expect(embedded(bytes).single, contains('ANSI'));
    });

    test('a plain pw.Font.ttf covering Bengali is shaped, not ignored',
        () async {
      // The caller never had to hear about loadFont: naming a Bangla TTF in an
      // ordinary TextStyle is enough.
      final bytes = await styled(fixture('SolaimanLipi.ttf'));
      expect(wasShaped(bytes), isTrue);
      expect(embedded(bytes).single, contains('SolaimanLipi'));
    });

    test('a legacy Bijoy font is honoured, not silently replaced', () async {
      for (final name in const <String>[
        'SiyamRupali-ANSI.ttf',
        'Kalpurush-ANSI.ttf',
      ]) {
        final font = fixture(name);
        final bytes = await styled(font);
        // Shaping declines so the Bijoy pipeline runs, and the caller's font
        // is the one embedded -- not the bundled Unicode Kalpurush.
        expect(wasShaped(bytes), isFalse, reason: name);
        expect(embedded(bytes).single, contains('ANSI'), reason: name);
      }
    });

    test('a Latin-only font leaves Bangla to the bundled face', () async {
      // Helvetica and friends must not disable shaping just by being current.
      final bytes = await styled(fixture('Kalpurush-Subset.ttf'));
      expect(wasShaped(bytes), isTrue);
    });
  });

  group('configuration still applies', () {
    test('legacy mode routes the compat widgets to the old pipeline', () async {
      BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy);
      final bytes = await page(pw.Text('আমার সোনার বাংলা'));
      // The legacy path writes Bijoy ANSI, so nothing is shaped and no
      // Bengali codepoint reaches the file.
      expect(wasShaped(bytes), isFalse);
      expect(latin1.decode(bytes, allowInvalid: true), isNot(contains('আ')));
    });
  });
}
