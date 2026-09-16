// A real government PDF exported from Microsoft Word.
//
// `test/fixtures/real/nctb-assessment-guideline-2026.pdf` is the NCTB primary
// assessment guideline (56 pages), written in Word 2013 with NikoshBAN,
// SutonnyMJ and Vrinda. It was reported as extracting badly, and it is a good
// example of how Word breaks Bangla text layers — every problem below was found
// in it, and poppler and pdf.js get it wrong in the same ways:
//
//  * Word's /ToUnicode CMaps pair glyphs with characters by *position*, so
//    every pair Bengali reorders is exchanged: ি with শ, ে with দ, র with ে.
//    Which pairs depends on the document's words, so no fixed table can undo
//    it; the text has to be read back through the embedded font instead.
//  * It draws one glyph per `Tj`, and on justified lines gives each glyph its
//    own text object and a structure tag, so no single operator holds a
//    cluster.
//  * Its WinAnsi subset of NikoshBAN has no Bengali in its cmap, and was taken
//    for Bijoy by name — turning page numbers into noise.
//  * It shows a lone byte with a two-byte CID font, which is not a glyph.
//  * Its SutonnyMJ runs use alternate Bijoy codes (`Ö`, `†`) the conversion
//    table never contained.
//
// Nothing here knows the exact text, so the checks are what can be known: that
// the Bangla is well-formed, that known passages come back, and that the scan
// pages are treated as scans. The npm package `bangla-pdf` carries the same
// fixture and the same checks, and the two produce byte-identical text.
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/extract.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixture = 'test/fixtures/real/nctb-assessment-guideline-2026.pdf';

/// Compares spellings rather than encodings, and ignores how lines wrap.
///
/// The nukta letters and two-part vowels have two spellings of the same text,
/// so both are folded onto their decomposed form. The pairs are built from
/// numbers because a literal, or even an escape, can be normalised on its way
/// into this file by an editor or a tool, leaving a replacement that does
/// nothing.
String _norm(String s) {
  String c(List<int> codes) => String.fromCharCodes(codes);
  var out = s;
  for (final (composed, parts) in <(int, List<int>)>[
    (0x09DC, <int>[0x09A1, 0x09BC]),
    (0x09DD, <int>[0x09A2, 0x09BC]),
    (0x09DF, <int>[0x09AF, 0x09BC]),
    (0x09CB, <int>[0x09C7, 0x09BE]),
    (0x09CC, <int>[0x09C7, 0x09D7]),
  ]) {
    out = out.replaceAll(c(<int>[composed]), c(parts));
  }
  return out.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
}

/// Words Unicode spelling rules out: starting with a dependent vowel sign, a
/// virama or a nasal mark, or carrying two vowel signs in a row. Scrambled
/// Bengali produces them in bulk; poppler's reading of this file is a quarter
/// such words.
List<String> _malformedWords(String text) {
  bool isSign(int c) => (c >= 0x09BE && c <= 0x09CC) || c == 0x09D7;
  final bad = <String>[];
  for (final m in RegExp('[ঀ-৿]+').allMatches(text)) {
    final cs = m.group(0)!.runes.toList();
    final first = cs.first;
    final leading = isSign(first) ||
        first == 0x09CD ||
        (first >= 0x0981 && first <= 0x0983);
    var doubled = false;
    for (var i = 1; i < cs.length; i++) {
      if (isSign(cs[i]) && isSign(cs[i - 1])) doubled = true;
    }
    if (leading || doubled) bad.add(m.group(0)!);
  }
  return bad;
}

void main() {
  late ExtractionResult result;
  final offeredToOcr = <int>[];

  setUpAll(() {
    result = BanglaPdfExtractor.extract(
      Uint8List.fromList(File(_fixture).readAsBytesSync()),
      ocrHook: (page) {
        offeredToOcr.add(page.number);
        return null;
      },
    );
  });

  group('a Word export with a scrambled text layer', () {
    test('reads as well-formed Bangla', () {
      final words = RegExp('[ঀ-৿]+').allMatches(result.text).length;
      final bad = _malformedWords(result.text);
      expect(words, greaterThan(10000));
      // One word at the time of writing, out of over fourteen thousand.
      expect(
        bad.length / words,
        lessThan(0.002),
        reason: bad.take(20).join(' '),
      );
    });

    test('recovers known passages exactly', () {
      final text = _norm(result.text);
      for (final passage in const <String>[
        'জাতীয় শিক্ষাক্রম ও পাঠ্যপুস্তক বোর্ড, বাংলাদেশ',
        'প্রাথমিক স্তরের মূল্যায়ন নির্দেশিকা',
        'প্রথম শ্রেণি থেকে পঞ্চম শ্রেণি',
        // Reordered pairs Word's CMap exchanges.
        'মূল্যায়ন শিক্ষাক্রমের একটি অবিচ্ছেদ্য অংশ',
        // A reph fused with its vowel sign, and a ya-phala before a pre-base
        // sign.
        'কার্যকর মূল্যায়ন পদ্ধতি প্রণয়নের লক্ষ্যে',
        'প্রাথমিক স্তরের শিক্ষার্থীদের জন্য একটি',
        // A justified line, one text object per glyph.
        'যৌক্তিক সমন্বয়ের মাধ্যমে',
        '১ম প্রান্তিকে মোট ৫২০, ২য় প্রান্তিকে মোট ৫৮০',
      ]) {
        expect(text, contains(_norm(passage)), reason: passage);
      }
    });

    test('names vowel signs the font subset pruned from its cmap', () {
      // `তৃ` is one glyph, and ৃ is not in the subset's cmap. Word's CMap calls
      // the glyph `র্ত`, having first met it in কর্তৃপক্ষ, where the reph
      // follows it.
      final text = _norm(result.text);
      int count(String word) => _norm(word).allMatches(text).length;
      expect(count('র্ততীয়'), 0);
      expect(count('তৃতীয়'), greaterThanOrEqualTo(37));
      expect(text, contains(_norm('কর্তৃপক্ষ')));
      expect(text, contains(_norm('নেতৃত্বে')));
      // Drawn with the vowel sign before the ya-phala.
      expect(text, contains(_norm('ন্যূনতম')));
      expect(text, isNot(matches(RegExp(r'[\u09BE-\u09CC]\u09CD'))));
    });

    test('does not split words inside table cells', () {
      // Word clips each glyph of a cell with `q … re W* n … Q`, which says
      // nothing about words; its spaces there are one-byte `( )` shows.
      final text = _norm(result.text);
      for (final split in const <String>[
        'ব ণ্ট ন',
        'খ্রী ষ্ট',
        'ঘ ণ্টা',
        'উ ত্তর'
      ]) {
        expect(text, isNot(contains(_norm(split))), reason: split);
      }
      for (final passage in const <String>[
        'বণ্টন',
        'খ্রীষ্ট',
        '১:০০ ঘণ্টা',
        'একাধিক অংশ থাকবে না',
        'জ্ঞান- ৩টি, দক্ষতা- ৩টি',
      ]) {
        expect(text, contains(_norm(passage)), reason: passage);
      }
    });

    test('does not invent symbols from bytes that are not glyphs', () {
      // A space shown as one byte with a two-byte font was read as glyph 32,
      // `=`, thousands of times. What is left are the formulas' own equals.
      expect(result.pages.first.text, isNot(contains('=')));
      expect('='.allMatches(result.text).length, lessThan(200));
    });

    test('converts the Bijoy runs, alternate codes included', () {
      expect(
        result.text,
        isNot(matches(RegExp(
          '[ঀ-৿][Ö†]|[Ö†][ঀ-৿]',
        ))),
      );
    });

    test('does not call a page Bijoy because of its page number', () {
      // Pages 12-15 are scans whose only text is a page number drawn in a
      // WinAnsi subset of NikoshBAN — a Unicode font, which has no Bengali
      // cmap entries left but still carries a Bengali GSUB.
      for (final number in const <int>[12, 13, 14, 15]) {
        final page = result.pages[number - 1];
        expect(
          page.encodingDetected,
          isNot(BanglaTextEncoding.bijoy),
          reason: 'page $number',
        );
        expect(page.hasImages, isTrue, reason: 'page $number');
      }
    });

    test('offers the scanned pages to OCR, and only those', () {
      expect(offeredToOcr, <int>[12, 13, 14, 15]);
    });

    test('reports inference as inference', () {
      // Most of the text had to be read back through the fonts, which counts
      // for less than text a document states outright.
      expect(result.confidence, greaterThan(0.5));
      expect(result.confidence, lessThan(1));
    });
  });

  test('SutonnyMJ alternate codes read the same as the canonical ones', () {
    expect(bijoyToUnicode('cÖ_g †kÖwY'), bijoyToUnicode('cª_g ‡kªwY'));
    expect(_norm(bijoyToUnicode('cÖ_g †kÖwY')), _norm('প্রথম শ্রেণি'));
    expect(_norm(bijoyToUnicode('cÖvwšÍK')), _norm('প্রান্তিক'));
  });
}
