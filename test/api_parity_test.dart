// Passing a value that happens to equal the default is the whole point here:
// the test exists to prove the parameter is still accepted.
// ignore_for_file: avoid_redundant_argument_values

// Every widget here is meant to be a drop-in for its `package:pdf` counterpart,
// so this file exercises the full parameter set of each. It is mostly a
// compile-time check: if a parameter is dropped or renamed, this stops
// building, which is the failure mode worth catching.
import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  tearDown(BanglaPdf.reset);

  test('Text accepts everything pw.Text does', () async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => Text(
          'বাংলা',
          style: const pw.TextStyle(fontSize: 12),
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.ltr,
          softWrap: true,
          tightBounds: false,
          textScaleFactor: 1.0,
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
        ),
      ),
    );
    expect((await pdf.save()).length, greaterThan(1000));
  });

  test('every widget accepts its full parameter set and renders', () async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (context) => <pw.Widget>[
          Header(
            'বাংলা শিরোনাম',
            level: 1,
            title: 'outline entry',
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(4),
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            textStyle: const pw.TextStyle(fontSize: 20),
            outlineColor: PdfColors.blue,
            outlineStyle: PdfOutlineStyle.bold,
          ),
          Paragraph(
            'একটি অনুচ্ছেদ।',
            textAlign: pw.TextAlign.justify,
            margin: const pw.EdgeInsets.all(4),
            padding: const pw.EdgeInsets.all(2),
          ),
          RichText(
            spans: <TextSpan>[
              TextSpan(
                'বোল্ড ',
                style: const pw.TextStyle(fontSize: 18, color: PdfColors.red),
              ),
              TextSpan('সাধারণ'),
            ],
            textAlign: pw.TextAlign.start,
            textDirection: pw.TextDirection.ltr,
            softWrap: true,
            tightBounds: false,
            textScaleFactor: 1.0,
            maxLines: 3,
            overflow: pw.TextOverflow.clip,
          ),
          BulletList(
            items: const <String>['এক', 'দুই'],
            itemSpacing: 3,
            bulletColor: PdfColors.blue,
            margin: const pw.EdgeInsets.all(2),
            padding: const pw.EdgeInsets.all(1),
            textAlign: pw.TextAlign.start,
          ),
          Table(
            data: const <List<String>>[
              <String>['ক', 'খ'],
              <String>['১', '২'],
              <String>['৩', '৪'],
            ],
            headerCount: 1,
            headerHeight: 24,
            cellHeight: 20,
            headerTextColor: PdfColors.white,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignments: const <int, pw.AlignmentGeometry>{
              1: pw.Alignment.centerRight,
            },
            tableWidth: pw.TableWidth.max,
            defaultColumnWidth: const pw.FlexColumnWidth(),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
        ],
      ),
    );
    expect((await pdf.save()).length, greaterThan(1000));
  });

  test('a header with no header rows still renders its data', () async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => Table(
          data: const <List<String>>[
            <String>['ক', 'খ'],
          ],
          headerCount: 0,
        ),
      ),
    );
    expect((await pdf.save()).length, greaterThan(1000));
  });

  test('TextSpan style wins over the loose parameters', () {
    final span = TextSpan(
      'বাংলা',
      fontSize: 10,
      color: PdfColors.black,
      style: const pw.TextStyle(fontSize: 22, color: PdfColors.red),
    );
    expect(span.effectiveFontSize, 22);
    expect(span.effectiveColor, PdfColors.red);
  });
}
