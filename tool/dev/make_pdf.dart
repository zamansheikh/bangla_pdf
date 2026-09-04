// Development harness: builds a PDF straight from the shaping pipeline,
// bypassing the Flutter-dependent public widgets.
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/src/widgets/shaped_text.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main(List<String> args) async {
  final fontPath = args[0];
  final outPath = args[1];
  final lines = args.length > 2
      ? args.sublist(2)
      : <String>['আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।'];

  final data = File(fontPath).readAsBytesSync();
  final font = BanglaUnicodeFont.tryParse(ByteData.sublistView(data))!;
  stderr.writeln('font=${font.fontName} canShapeBangla=${font.canShapeBangla}');

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          for (final line in lines) ...<pw.Widget>[
            ShapedTextWidget(
              text: line,
              font: font,
              fontSize: 18,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 6),
          ],
        ],
      ),
    ),
  );
  File(outPath).writeAsBytesSync(await doc.save());
  stderr.writeln('wrote $outPath (${File(outPath).lengthSync()} bytes)');
}
