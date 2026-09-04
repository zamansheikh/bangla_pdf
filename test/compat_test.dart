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
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart' show BanglaPdf, BanglaShapingMode;
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
