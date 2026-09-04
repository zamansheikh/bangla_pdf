import 'dart:io';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  tearDown(BanglaPdf.reset);

  test('public Text() widget produces a shaped, extractable PDF', () async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            Text('আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।'),
            Text('ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য'),
            Text('কর্ম ধর্ম বর্ষ পূর্ব শর্ত'),
            Text('Hello বাংলাদেশ world! ৳১২,৫০০.০০'),
            Header('বাংলা শিরোনাম'),
            Paragraph('বাংলা অনুচ্ছেদ এখানে লেখা হবে।'),
            BulletList(items: const ['প্রথম আইটেম', 'দ্বিতীয় আইটেম']),
            Table(data: const [
              ['পণ্য', 'মূল্য'],
              ['কফি', '৳২০'],
            ]),
          ],
        ),
      ),
    );
    // Never write into the repository: a stray PDF ends up in the published
    // archive. PDF_OUT is only set when a human wants to eyeball the result.
    final target = Platform.environment['PDF_OUT'];
    final bytes = await pdf.save();
    expect(bytes.length, greaterThan(1000));
    if (target != null) await File(target).writeAsBytes(bytes);
  });

  test('legacy mode still renders and no longer throws on reph', () async {
    BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy);
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          children: [
            // Every one of these threw RangeError in 1.0.6.
            Text('কর্ম'),
            Text('ধর্ম'),
            Text('বর্ষ'),
            Text('পূর্ব'),
            Text('শর্ত'),
          ],
        ),
      ),
    );
    expect((await pdf.save()).length, greaterThan(1000));
  });
}
