// Extraction against documents this package did not produce.
//
// Generated fixtures prove the pipeline is self-consistent. They cannot prove
// anything about a file written by some other tool years ago, which is what
// users actually feed it. Drop PDFs into test/fixtures/real/ and this runs
// over them; see the README there.
//
// The assertions are deliberately about *honesty* rather than content, since
// the expected text of an arbitrary document is unknown: a document with no
// text layer must say so rather than invent something, and one with text must
// not come back empty.
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/extract.dart';
import 'package:flutter_test/flutter_test.dart';

List<File> realDocuments() {
  final dir = Directory('test/fixtures/real');
  if (!dir.existsSync()) return <File>[];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList();
}

void main() {
  final documents = realDocuments();

  test('every real document is read without throwing', () {
    if (documents.isEmpty) {
      markTestSkipped('no documents in test/fixtures/real');
      return;
    }
    for (final file in documents) {
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      expect(
        () => BanglaPdfExtractor.extract(bytes),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test('a document with no text layer is never given one', () {
    if (documents.isEmpty) {
      markTestSkipped('no documents in test/fixtures/real');
      return;
    }
    for (final file in documents) {
      final result = BanglaPdfExtractor.extract(
        Uint8List.fromList(file.readAsBytesSync()),
      );
      if (result.encodingDetected != BanglaTextEncoding.none) continue;

      // Reporting `none` is a claim that the document carries no text. It has
      // to be true, and the pages have to be marked as scans so a caller knows
      // to reach for OCR.
      expect(result.text.trim(), isEmpty, reason: file.path);
      expect(result.confidence, 0.0, reason: file.path);
      expect(
        result.pages.every((p) => p.hasImages),
        isTrue,
        reason: '${file.path}: reported no text but no images either',
      );
    }
  });

  test('a document with text comes back with some', () {
    if (documents.isEmpty) {
      markTestSkipped('no documents in test/fixtures/real');
      return;
    }
    for (final file in documents) {
      final result = BanglaPdfExtractor.extract(
        Uint8List.fromList(file.readAsBytesSync()),
      );
      if (result.encodingDetected == BanglaTextEncoding.none) continue;
      expect(result.text.trim(), isNotEmpty, reason: file.path);
      expect(result.pages, isNotEmpty, reason: file.path);
    }
  });

  test('the OCR hook is offered every page that needs it', () {
    if (documents.isEmpty) {
      markTestSkipped('no documents in test/fixtures/real');
      return;
    }
    for (final file in documents) {
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      final plain = BanglaPdfExtractor.extract(bytes);
      if (plain.encodingDetected != BanglaTextEncoding.none) continue;

      final offered = <int>[];
      final withOcr = BanglaPdfExtractor.extract(
        bytes,
        ocrHook: (page) {
          offered.add(page.number);
          return 'পৃষ্ঠা ${page.number}';
        },
      );
      expect(offered.length, plain.pages.length, reason: file.path);
      expect(withOcr.text.trim(), isNotEmpty, reason: file.path);
    }
  });
}
