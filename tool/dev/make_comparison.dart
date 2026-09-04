// Renders the same Bangla twice — once through the 1.0.x Bijoy pipeline and
// once through the OpenType shaper — to produce the README comparison image.
import 'dart:io';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const samples = <(String, String)>[
  ('Conjuncts', 'ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য'),
  ('Reph', 'কর্ম ধর্ম বর্ষ পূর্ব শর্ত'),
  ('Vowel signs', 'কি কে কৈ কো কৌ কা কু'),
  ('Digits & currency', '০১২৩৪৫৬৭৮৯ ৳১২,৫০০.০০'),
  ('Prose', 'আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।'),
];

/// [banglaFont] selects the pipeline per widget rather than globally: the
/// legacy 8-bit font routes to the 1.0.x Bijoy path, the default one to the
/// shaper. A global mode switch would not work here, because both columns are
/// laid out after the tree is built and the last setting would win for both.
pw.Widget column(
  String heading,
  String note,
  PdfColor accent,
  pw.Font? banglaFont,
) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: accent, width: 1.2),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(heading,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent)),
          pw.Text(note,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 10),
          for (final (label, text) in samples) ...<pw.Widget>[
            pw.Text(label,
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            Text(text, fontSize: 13, banglaFont: banglaFont),
            pw.SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

Future<void> main(List<String> args) async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(560, 300, marginAll: 14),
      build: (context) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          column(
            '1.0.6  -  Bijoy ANSI',
            'broken conjuncts; reph crashed pdf.save() outright',
            PdfColors.red700,
            BanglaFontManager().legacyFont,
          ),
          pw.SizedBox(width: 12),
          column(
            '1.1.0  -  OpenType shaping',
            'correct glyphs, and the text copies out as Unicode',
            PdfColors.green800,
            null,
          ),
        ],
      ),
    ),
  );
  File(args[0]).writeAsBytesSync(await pdf.save());
  BanglaPdf.reset();
}
