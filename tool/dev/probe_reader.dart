import 'dart:io';
import 'dart:typed_data';
import 'package:bangla_pdf/src/extract/pdf_object.dart';
import 'package:bangla_pdf/src/extract/pdf_reader.dart';

void main(List<String> args) {
  for (final p in args) {
    final r = PdfReader.open(Uint8List.fromList(File(p).readAsBytesSync()));
    if (r == null) {
      print('$p: not a PDF');
      continue;
    }
    final pages = r.pages();
    print(
        '${p.split('/').last}: ${pages.length} pages, encrypted=${r.isEncrypted}');
    for (var i = 0; i < pages.length && i < 2; i++) {
      final content = r.contentOf(pages[i]);
      final res = r.resolve(pages[i]['Resources']);
      final fonts =
          res is PdfDictObj ? r.resolve(res['Font']) : const PdfNullObj();
      final names =
          fonts is PdfDictObj ? fonts.entries.keys.toList() : <String>[];
      print('  page ${i + 1}: content=${content.length}B fonts=$names');
    }
  }
}
