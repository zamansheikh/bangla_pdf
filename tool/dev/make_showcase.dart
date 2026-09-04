// Builds the README's example documents. Every one is real output from the
// public widgets — nothing here is mocked up in a design tool.
import 'dart:io';

import 'package:bangla_pdf/bangla_pdf.dart';
// The dashboard below is written against the drop-in entry point, so this file
// exercises both APIs the package offers.
import 'package:bangla_pdf/widgets.dart' as bpw;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF6B7A8C);
const _brand = PdfColor.fromInt(0xFF0F766E);
const _brandSoft = PdfColor.fromInt(0xFFE6F4F1);
const _line = PdfColor.fromInt(0xFFDCE3EA);
const _band = PdfColor.fromInt(0xFFF6F8FA);

/// An invoice: table styling, Bengali digits and the taka sign.
pw.Document invoice() {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(430, 400, marginAll: 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  Text('চালান',
                      fontSize: 26,
                      style: pw.TextStyle(color: _brand, lineSpacing: 1)),
                  Text('ইনভয়েস নং ২০২৬-০৯১২', fontSize: 10, color: _muted),
                ],
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _brandSoft,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: Text('পরিশোধিত', fontSize: 10, color: _brand),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    Text('বিক্রেতা', fontSize: 8, color: _muted),
                    Text('সিলিফটন টেকনোলজিস', fontSize: 11, color: _ink),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    Text('ক্রেতা', fontSize: 8, color: _muted),
                    Text('মোহাম্মদ রফিকুল ইসলাম', fontSize: 11, color: _ink),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          Table(
            data: const <List<String>>[
              <String>['বিবরণ', 'পরিমাণ', 'একক মূল্য', 'মোট'],
              <String>['কম্পিউটার যন্ত্রাংশ', '৩', '৳১২,৫০০', '৳৩৭,৫০০'],
              <String>['কীবোর্ড ও মাউস', '২', '৳২,২৫০', '৳৪,৫০০'],
              <String>['বার্ষিক রক্ষণাবেক্ষণ', '১', '৳৮,০০০', '৳৮,০০০'],
            ],
            fontSize: 10,
            headerTextColor: PdfColors.white,
            headerDecoration: const pw.BoxDecoration(color: _brand),
            headerHeight: 26,
            cellHeight: 24,
            oddRowDecoration: const pw.BoxDecoration(color: _band),
            cellAlignments: const <int, pw.AlignmentGeometry>{
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
            ),
            cellTextColor: _ink,
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: <pw.Widget>[
              pw.Container(
                width: 190,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _brandSoft,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: <pw.Widget>[
                    Text('সর্বমোট', fontSize: 11, color: _brand),
                    Text('৳৫০,০০০', fontSize: 15, color: _brand),
                  ],
                ),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Divider(color: _line, thickness: 0.5),
          Text('ধন্যবাদ — পরিশোধের শেষ তারিখ ৩০/০৯/২০২৬',
              fontSize: 9, color: _muted),
        ],
      ),
    ),
  );
  return pdf;
}

/// A letter: headings, paragraphs and a bulleted list at reading sizes.
pw.Document notice() {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(430, 520, marginAll: 30),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 2)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                Text('ঢাকা বিশ্ববিদ্যালয়', fontSize: 20, color: _ink),
                Text('রেজিস্ট্রার দপ্তর', fontSize: 10, color: _muted),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          Header('ভর্তি বিজ্ঞপ্তি',
              fontSize: 16,
              level: 1,
              margin: const pw.EdgeInsets.only(bottom: 10),
              textStyle: const pw.TextStyle(color: _brand)),
          Paragraph(
            'সকল শিক্ষার্থীর অবগতির জন্য জানানো যাচ্ছে যে, আগামী শিক্ষাবর্ষের '
            'ভর্তি কার্যক্রম সম্পূর্ণ অনলাইনে সম্পন্ন হবে। নির্ধারিত তারিখের '
            'মধ্যে আবেদন সম্পন্ন করতে হবে।',
            fontSize: 11,
            textAlign: pw.TextAlign.justify,
          ),
          Header('প্রয়োজনীয় কাগজপত্র',
              fontSize: 13,
              level: 2,
              margin: const pw.EdgeInsets.only(top: 4, bottom: 8),
              textStyle: const pw.TextStyle(color: _ink)),
          BulletList(
            items: const <String>[
              'এসএসসি ও এইচএসসি পরীক্ষার মূল সনদপত্র',
              'জন্ম নিবন্ধন সনদ অথবা জাতীয় পরিচয়পত্র',
              'সদ্য তোলা পাসপোর্ট সাইজের ছবি',
            ],
            fontSize: 11,
            bulletSize: 4,
            bulletColor: _brand,
            itemSpacing: 5,
            color: _ink,
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _band,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: _line, width: 0.5),
            ),
            child: Text(
              'কর্তৃপক্ষের নির্দেশক্রমে জারি করা হলো। বিস্তারিত জানতে '
              'সংশ্লিষ্ট কার্যালয়ে যোগাযোগ করুন।',
              fontSize: 10,
              color: _muted,
            ),
          ),
          pw.Spacer(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              Text('স্বাক্ষরিত', fontSize: 10, color: _muted),
              Text('রেজিস্ট্রার', fontSize: 11, color: _ink),
              Text('তারিখ: ০১/০৯/২০২৬', fontSize: 9, color: _muted),
            ],
          ),
        ],
      ),
    ),
  );
  return pdf;
}

/// A report: mixed Bangla and Latin, a data table and a summary strip.
pw.Document report() {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(430, 520, marginAll: 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          Text('Q3 বিক্রয় প্রতিবেদন', fontSize: 20, color: _ink),
          Text('জুলাই — সেপ্টেম্বর ২০২৬  ·  Silifton Technologies',
              fontSize: 9, color: _muted),
          pw.SizedBox(height: 16),
          pw.Row(
            children: <pw.Widget>[
              for (final stat in const <List<String>>[
                <String>['মোট বিক্রয়', '৳৪২.৫ লক্ষ'],
                <String>['নতুন গ্রাহক', '১,২৪৮'],
                <String>['বৃদ্ধি', '+১৮%'],
              ])
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.only(right: 8),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: _band,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        Text(stat[0], fontSize: 8, color: _muted),
                        pw.SizedBox(height: 2),
                        Text(stat[1], fontSize: 14, color: _brand),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 18),
          Header('বিভাগভিত্তিক ফলাফল',
              fontSize: 13,
              level: 2,
              margin: const pw.EdgeInsets.only(bottom: 8),
              textStyle: const pw.TextStyle(color: _ink)),
          Table(
            data: const <List<String>>[
              <String>['বিভাগ', 'Region', 'বিক্রয়', 'পরিবর্তন'],
              <String>['কর্পোরেট', 'Dhaka', '৳১৮.২ লক্ষ', '+২২%'],
              <String>['খুচরা', 'Chattogram', '৳১২.৭ লক্ষ', '+১৪%'],
              <String>['অনলাইন', 'Nationwide', '৳১১.৬ লক্ষ', '+১৯%'],
            ],
            fontSize: 10,
            headerTextColor: _ink,
            headerDecoration: const pw.BoxDecoration(color: _band),
            headerHeight: 24,
            cellHeight: 22,
            cellAlignments: const <int, pw.AlignmentGeometry>{
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
              bottom: pw.BorderSide(color: _line, width: 0.5),
            ),
            cellTextColor: _ink,
          ),
          pw.SizedBox(height: 16),
          Paragraph(
            'কর্পোরেট বিভাগে প্রবৃদ্ধি সবচেয়ে বেশি, মূলত দীর্ঘমেয়াদী '
            'চুক্তির কারণে। পরবর্তী প্রান্তিকে অনলাইন বিভাগে বিনিয়োগ '
            'বাড়ানোর সুপারিশ করা হচ্ছে।',
            fontSize: 10,
            textAlign: pw.TextAlign.justify,
          ),
          pw.Spacer(),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
            ),
            child: Text('প্রস্তুতকারী: বিশ্লেষণ দল  ·  পৃষ্ঠা ১/১',
                fontSize: 8, color: _muted),
          ),
        ],
      ),
    ),
  );
  return pdf;
}

/// A statement with a chart: Bangla axis labels, a Bangla legend and Bengali
/// digits throughout. Written with the `package:bangla_pdf/widgets.dart`
/// drop-in, so every widget below is a `package:pdf` widget by name.
bpw.Document dashboard() {
  const months = <String>['জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন'];
  const sales = <double>[42, 58, 51, 73, 68, 91];

  bpw.Widget metric(String label, String value, String delta) => bpw.Expanded(
        child: bpw.Container(
          padding: const bpw.EdgeInsets.all(11),
          margin: const bpw.EdgeInsets.only(right: 8),
          decoration: bpw.BoxDecoration(
            color: _band,
            borderRadius: bpw.BorderRadius.circular(5),
          ),
          child: bpw.Column(
            crossAxisAlignment: bpw.CrossAxisAlignment.start,
            children: <bpw.Widget>[
              bpw.Text(label,
                  style: const bpw.TextStyle(fontSize: 8, color: _muted)),
              bpw.SizedBox(height: 3),
              bpw.Text(value,
                  style: const bpw.TextStyle(fontSize: 15, color: _ink)),
              bpw.SizedBox(height: 2),
              bpw.Text(delta,
                  style: const bpw.TextStyle(fontSize: 8, color: _brand)),
            ],
          ),
        ),
      );

  final pdf = bpw.Document();
  pdf.addPage(
    bpw.Page(
      pageFormat: PdfPageFormat(430, 560, marginAll: 26),
      build: (context) => bpw.Column(
        crossAxisAlignment: bpw.CrossAxisAlignment.start,
        children: <bpw.Widget>[
          bpw.Row(
            mainAxisAlignment: bpw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: bpw.CrossAxisAlignment.start,
            children: <bpw.Widget>[
              bpw.Column(
                crossAxisAlignment: bpw.CrossAxisAlignment.start,
                children: <bpw.Widget>[
                  bpw.Text('ষাণ্মাসিক প্রতিবেদন',
                      style: const bpw.TextStyle(
                          fontSize: 22, color: _brand, lineSpacing: 1)),
                  bpw.SizedBox(height: 2),
                  bpw.Text('জানুয়ারি — জুন ২০২৬',
                      style: const bpw.TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
              bpw.Container(
                padding:
                    const bpw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: bpw.BoxDecoration(
                  color: _brandSoft,
                  borderRadius: bpw.BorderRadius.circular(4),
                ),
                child: bpw.Text('চূড়ান্ত',
                    style: const bpw.TextStyle(fontSize: 9, color: _brand)),
              ),
            ],
          ),
          bpw.SizedBox(height: 16),
          bpw.Row(children: <bpw.Widget>[
            metric('মোট বিক্রয়', '৳৩৮৩ কোটি', '+২১.৪% বৃদ্ধি'),
            metric('নতুন গ্রাহক', '১২,৪৭৯', '+৮.১% বৃদ্ধি'),
            metric('গড় মূল্য', '৳৮,৭৫০', '+৩.২% বৃদ্ধি'),
          ]),
          bpw.SizedBox(height: 20),
          bpw.Text('মাসভিত্তিক বিক্রয়',
              style: const bpw.TextStyle(fontSize: 12, color: _ink)),
          bpw.SizedBox(height: 10),
          bpw.SizedBox(
            height: 175,
            child: bpw.Chart(
              grid: bpw.CartesianGrid(
                xAxis: bpw.FixedAxis.fromStrings(
                  months,
                  textStyle: const bpw.TextStyle(fontSize: 8, color: _muted),
                  marginStart: 24,
                  marginEnd: 16,
                ),
                yAxis: bpw.FixedAxis<int>(
                  const <int>[0, 25, 50, 75, 100],
                  textStyle: const bpw.TextStyle(fontSize: 8, color: _muted),
                  divisions: true,
                  divisionsColor: _line,
                  format: _bengaliNumber,
                ),
              ),
              overlay: bpw.ChartLegend(
                position: bpw.Alignment.topRight,
                direction: bpw.Axis.horizontal,
                textStyle: const bpw.TextStyle(fontSize: 8, color: _muted),
                decoration: const bpw.BoxDecoration(),
                padding: bpw.EdgeInsets.zero,
              ),
              datasets: <bpw.Dataset>[
                bpw.BarDataSet(
                  legend: 'বিক্রয় (কোটি টাকা)',
                  color: _brand,
                  width: 20,
                  data: <bpw.PointChartValue>[
                    for (var i = 0; i < sales.length; i++)
                      bpw.PointChartValue(i.toDouble(), sales[i]),
                  ],
                ),
              ],
            ),
          ),
          bpw.SizedBox(height: 18),
          bpw.Divider(color: _line, thickness: 0.6),
          bpw.SizedBox(height: 10),
          bpw.Text(
            'উপরের চিত্রে দেখা যাচ্ছে, দ্বিতীয় প্রান্তিকে বিক্রয় উল্লেখযোগ্যভাবে '
            'বৃদ্ধি পেয়েছে। কর্তৃপক্ষ মনে করছে এই ধারা আগামী প্রান্তিকেও '
            'অব্যাহত থাকবে।',
            textAlign: bpw.TextAlign.justify,
            style: const bpw.TextStyle(
                fontSize: 9.5, color: _muted, lineSpacing: 1.5),
          ),
        ],
      ),
    ),
  );
  return pdf;
}

/// Formats an axis value with Bengali digits.
String _bengaliNumber(num value) {
  const digits = <String>['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return value
      .toInt()
      .toString()
      .split('')
      .map((d) => digits[int.parse(d)])
      .join();
}

/// Writes every showcase document into [directory].
Future<void> buildShowcase(String directory) async {
  BanglaPdf.reset();
  Directory(directory).createSync(recursive: true);
  final documents = <String, pw.Document>{
    'sample-dashboard': dashboard(),
    'sample-invoice': invoice(),
    'sample-notice': notice(),
    'sample-report': report(),
  };
  for (final entry in documents.entries) {
    File('$directory/${entry.key}.pdf')
        .writeAsBytesSync(await entry.value.save());
  }
}
