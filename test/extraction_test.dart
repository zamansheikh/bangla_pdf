import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:bangla_pdf/extract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

/// Folds away spelling differences Bijoy cannot carry, and collapses runs of
/// whitespace so line wrapping does not count as a mismatch.
String normalise(String s) => s
    .replaceAll('ড়', 'ড়')
    .replaceAll('ঢ়', 'ঢ়')
    .replaceAll('য়', 'য়')
    .replaceAll('ো', 'ো')
    .replaceAll('ৌ', 'ৌ')
    .replaceAll('‌', '')
    .replaceAll('‍', '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .join(' ');

List<Map<String, dynamic>> loadGroundTruth() {
  final file = File('test/fixtures/pdfs/ground_truth.json');
  if (!file.existsSync()) return const <Map<String, dynamic>>[];
  return (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
}

Uint8List fixtureBytes(String name) =>
    Uint8List.fromList(File('test/fixtures/pdfs/$name.pdf').readAsBytesSync());

Future<Uint8List> render(List<String> lines, {pw.Font? banglaFont}) {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          for (final line in lines) Text(line, banglaFont: banglaFont),
        ],
      ),
    ),
  );
  return pdf.save();
}

void main() {
  tearDown(BanglaPdf.reset);

  group('round-trip through our own PDFs', () {
    test('text comes back exactly as it went in', () async {
      const lines = <String>[
        'আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।',
        'ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য',
        'কর্ম ধর্ম বর্ষ পূর্ব শর্ত',
        'Hello বাংলাদেশ world! ৳১২,৫০০.০০',
      ];
      final result = BanglaPdfExtractor.extract(await render(lines));
      expect(result.encodingDetected, BanglaTextEncoding.unicode);
      expect(result.confidence, 1.0);
      expect(normalise(result.text), normalise(lines.join(' ')));
    });

    test('a Bijoy document is detected and converted back', () async {
      const lines = <String>[
        'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার',
        'কর্তৃপক্ষের নির্দেশক্রমে জারি করা হলো।',
      ];
      final bytes = await render(
        lines,
        banglaFont: BanglaFontManager().legacyFont,
      );
      // The text layer really is Bijoy: no Bengali codepoint is in the file.
      expect(latin1.decode(bytes, allowInvalid: true), isNot(contains('আ')));

      final result = BanglaPdfExtractor.extract(bytes);
      expect(result.encodingDetected, BanglaTextEncoding.bijoy);
      expect(normalise(result.text), normalise(lines.join(' ')));
    });
  });

  group('real-world-shaped fixtures', () {
    test('every extractable fixture recovers its ground truth', () {
      final manifest = loadGroundTruth();
      if (manifest.isEmpty) {
        markTestSkipped('fixtures not present');
        return;
      }
      final failures = <String>[];
      for (final fixture in manifest) {
        if (fixture['extractable'] != true) continue;
        final name = fixture['name'] as String;
        final expected = (fixture['lines'] as List).cast<String>().join(' ');
        final result = BanglaPdfExtractor.extract(fixtureBytes(name));

        if (result.encodingDetected.name != fixture['encoding']) {
          failures.add('$name: encoding ${result.encodingDetected.name} '
              'but expected ${fixture['encoding']}');
        }
        if (normalise(result.text) != normalise(expected)) {
          failures.add('$name: text mismatch\n'
              '  expected: ${normalise(expected)}\n'
              '  actual  : ${normalise(result.text)}');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('a scan reports no text layer rather than guessing', () {
      final manifest = loadGroundTruth();
      if (manifest.isEmpty) {
        markTestSkipped('fixtures not present');
        return;
      }
      for (final fixture in manifest) {
        if (fixture['extractable'] == true) continue;
        final name = fixture['name'] as String;
        final result = BanglaPdfExtractor.extract(fixtureBytes(name));
        expect(result.encodingDetected, BanglaTextEncoding.none, reason: name);
        expect(result.text, isEmpty, reason: name);
        expect(result.confidence, 0.0, reason: name);
        expect(result.pages.single.hasImages, isTrue, reason: name);
      }
    });

    test('the OCR hook fills in a page with no text layer', () {
      final manifest = loadGroundTruth();
      final scanned = manifest
          .where((f) => f['extractable'] != true)
          .map((f) => f['name'] as String)
          .toList();
      if (scanned.isEmpty) {
        markTestSkipped('fixtures not present');
        return;
      }
      const recovered = 'ওসিআর থেকে পাওয়া লেখা';
      final result = BanglaPdfExtractor.extract(
        fixtureBytes(scanned.first),
        ocrHook: (page) => recovered,
      );
      expect(result.text, contains(recovered));
      expect(result.pages.single.encodingDetected, BanglaTextEncoding.unicode);
    });
  });

  group('Bijoy conversion', () {
    test('the whole corpus survives a Bijoy round-trip', () {
      final cases = (jsonDecode(
        File('test/corpus/bangla_cases.json').readAsStringSync(),
      ) as List)
          .cast<Map<String, dynamic>>();

      var ok = 0;
      var total = 0;
      final failures = <String>[];
      for (final c in cases) {
        final text = c['text'] as String;
        if (text.trim().isEmpty) continue;
        // Bijoy bytes are ambiguous: 'e' is English "e" and Bangla ব. Only a
        // run's font can tell them apart, so a whole-string conversion is only
        // meaningful for text with no Latin letters in it.
        if (RegExp('[A-Za-z]').hasMatch(text)) continue;
        total++;
        final back = bijoyToUnicode(text.fix);
        if (normalise(back) == normalise(text)) {
          ok++;
        } else {
          failures.add('[${c['id']}] $text -> $back');
        }
      }
      expect(total, greaterThan(200));
      // The shortfall is the joiner in বাক্‌, which the forward transform
      // deletes and no reverse mapping can invent.
      expect(ok / total, greaterThan(0.98), reason: failures.join('\n'));
    });

    test('a reph is put back in front of its cluster', () {
      expect(bijoyToUnicode('Kg©'), 'কর্ম');
      expect(bijoyToUnicode('ag©'), 'ধর্ম');
    });

    test('a ra-phala is not mistaken for a reph', () {
      // Both decode to র + virama; only the preceding character separates them.
      expect(bijoyToUnicode('Mª¨'), 'গ্র্য');
      expect(bijoyToUnicode('cª_g'), 'প্রথম');
    });

    test('pre-base vowel signs move back after their consonant', () {
      expect(bijoyToUnicode('wK'), 'কি');
      expect(bijoyToUnicode('‡K'), 'কে');
      expect(bijoyToUnicode('‡Kv'), 'কো');
    });

    test('digits and currency are restored, not left as ASCII', () {
      expect(bijoyToUnicode('0123456789'), '০১২৩৪৫৬৭৮৯');
      expect(bijoyToUnicode(r'$500'), '৳৫০০');
    });
  });

  group('robustness', () {
    test('junk input returns an empty result instead of throwing', () {
      for (final bytes in <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(<int>[1, 2, 3]),
        Uint8List.fromList(utf8.encode('not a pdf at all')),
      ]) {
        final result = BanglaPdfExtractor.extract(bytes);
        expect(result.encodingDetected, BanglaTextEncoding.none);
        expect(result.text, isEmpty);
      }
    });

    test('a truncated PDF still yields what it can', () async {
      final full = await render(const <String>['বাংলাদেশ']);
      final truncated = Uint8List.sublistView(full, 0, full.length - 64);
      // The cross-reference table is gone; the object scan has to recover it.
      final result = BanglaPdfExtractor.extract(truncated);
      expect(() => result.text, returnsNormally);
    });
  });
}
