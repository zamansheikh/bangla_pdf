// Renders every corpus case on its own line, one PDF per page batch, so the
// round-trip can be checked line by line with pdftotext.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/src/widgets/shaped_text.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main(List<String> args) async {
  final font = BanglaUnicodeFont.tryParse(
    ByteData.sublistView(File(args[0]).readAsBytesSync()),
  )!;
  final cases = (jsonDecode(File(args[1]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .where((c) => (c['text'] as String).trim().isNotEmpty)
      .toList();

  final doc = pw.Document();
  const perPage = 30;
  for (var start = 0; start < cases.length; start += perPage) {
    final slice = cases.skip(start).take(perPage).toList();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            for (final c in slice)
              ShapedTextWidget(
                text: c['text'] as String,
                font: font,
                fontSize: 13,
                color: PdfColors.black,
              ),
          ],
        ),
      ),
    );
  }
  File(args[2]).writeAsBytesSync(await doc.save());
  File('${args[2]}.ids').writeAsStringSync(
    cases.map((c) => '${c['id']}\t${c['text']}').join('\n'),
  );
  stderr.writeln('${cases.length} cases -> ${args[2]}');
}
