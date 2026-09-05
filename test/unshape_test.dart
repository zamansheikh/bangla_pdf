// Recovering text from glyph ids alone, for PDFs that offer nothing else.
//
// This is inference, not decoding: the font is read backwards to work out
// which characters would produce the glyphs that were drawn. So the tests
// measure how much comes back, and say plainly what cannot.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:bangla_pdf/extract.dart';
import 'package:bangla_pdf/src/extract/glyph_reverse.dart';
import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

/// Folds NFD onto NFC. The nukta letters and two-part vowels have two
/// spellings of the same text, and which one comes back is not a defect.
String norm(String s) => s
    .replaceAll('\u09A1\u09BC', '\u09DC') // \u09A1 + nukta -> \u09DC
    .replaceAll('\u09A2\u09BC', '\u09DD')
    .replaceAll('\u09AF\u09BC', '\u09DF')
    .replaceAll('\u09C7\u09BE', '\u09CB') // e + aa -> o
    .replaceAll('\u09C7\u09D7', '\u09CC') // e + au mark -> au
    .replaceAll('\u200C', '')
    .replaceAll('\u200D', '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .join(' ');

List<Map<String, dynamic>> corpus() =>
    (jsonDecode(File('test/corpus/bangla_cases.json').readAsStringSync())
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

/// Makes a document look like one from a producer that kept no text.
///
/// Breaking the two key names is enough: an extractor no longer recognises
/// either, so the only thing left is which glyph was drawn.
Uint8List stripTextMapping(Uint8List bytes) {
  final out = Uint8List.fromList(bytes);
  for (final key in <String>['/ToUnicode', '/ActualText']) {
    final needle = latin1.encode(key);
    for (var i = 0; i + needle.length <= out.length; i++) {
      var hit = true;
      for (var k = 0; k < needle.length; k++) {
        if (out[i + k] != needle[k]) {
          hit = false;
          break;
        }
      }
      // Rename the key rather than delete it, so every offset stays valid.
      if (hit) out[i + needle.length - 1] = 0x58; // 'X'
    }
  }
  return out;
}

void main() {
  tearDown(BanglaPdf.reset);

  group('reading a font backwards', () {
    test('the corpus comes back from glyph ids alone', () {
      final font = BanglaPdf.defaultFont as BanglaUnicodeFont;
      final reverse = GlyphReverseMap.build(font.otf);

      var recovered = 0;
      var total = 0;
      final missed = <String>[];
      for (final testCase in corpus()) {
        final text = testCase['text'] as String;
        if (text.trim().isEmpty) continue;
        total++;
        final back = reverse.decodeRun(
          font.shape(text).glyphs.map((g) => g.gid),
        );
        if (norm(back) == norm(text)) {
          recovered++;
        } else {
          missed.add('[${testCase['id']}] $text -> $back');
        }
      }

      // 243 of 251 at the time of writing. The shortfall is text that is not
      // in the glyphs at all: an emoji the font cannot draw, a ZWJ (which is
      // invisible and produces nothing), and the dotted circles the shaper
      // inserts for a vowel sign typed with no consonant.
      expect(total, greaterThan(200));
      expect(recovered / total, greaterThan(0.95), reason: missed.join('\n'));
    });

    test('a conjunct comes back whole, not as its parts', () {
      final font = BanglaPdf.defaultFont as BanglaUnicodeFont;
      final reverse = GlyphReverseMap.build(font.otf);
      for (final text in <String>[
        'ক্ষ্ম',
        'ঙ্ক্ষ',
        'শ্ব',
        'ব্য',
        'র্ক',
        'কি'
      ]) {
        expect(
          norm(reverse.decodeRun(font.shape(text).glyphs.map((g) => g.gid))),
          norm(text),
          reason: text,
        );
      }
    });

    test('reph and pre-base vowels are put back in typing order', () {
      final font = BanglaPdf.defaultFont as BanglaUnicodeFont;
      final reverse = GlyphReverseMap.build(font.otf);

      // Both are drawn in an order nobody types: the reph after its cluster,
      // the vowel sign before its consonant.
      for (final text in <String>['কর্ম', 'ধর্ম', 'কি', 'কে', 'কো']) {
        final gids = font.shape(text).glyphs.map((g) => g.gid).toList();
        expect(norm(reverse.decodeRun(gids)), norm(text), reason: text);
      }
    });
  });

  group('a document with no text layer of its own', () {
    Future<Uint8List> render(String text) {
      final pdf = pw.Document();
      pdf.addPage(pw.Page(build: (context) => pw.Text(text)));
      return pdf.save();
    }

    test('text is recovered where the document gives none', () async {
      const source = 'বাংলাদেশ সরকার';
      final stripped = stripTextMapping(await render(source));

      // Nothing in the file says what the codes mean any more.
      expect(latin1.decode(stripped, allowInvalid: true),
          isNot(contains('/ToUnicode')));
      expect(latin1.decode(stripped, allowInvalid: true),
          isNot(contains('/ActualText')));

      final result = BanglaPdfExtractor.extract(stripped);
      expect(norm(result.text), norm(source));
    });

    test('a document that does carry its text is left alone', () async {
      // The reverse map is a last resort and must never displace a real
      // /ToUnicode, which is authoritative where a reverse map only guesses.
      const source = 'গণপ্রজাতন্ত্রী বাংলাদেশ ক্ষ্ম কর্ম';
      final result = BanglaPdfExtractor.extract(await render(source));
      expect(norm(result.text), norm(source));
      expect(result.confidence, 1.0);
    });

    test('junk still yields nothing rather than throwing', () {
      final result = BanglaPdfExtractor.extract(
        Uint8List.fromList(utf8.encode('not a pdf')),
      );
      expect(result.text, isEmpty);
    });
  });
}
