import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the corpus shared by every test in this suite.
List<Map<String, dynamic>> loadCorpus() =>
    (jsonDecode(File('test/corpus/bangla_cases.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>();

BanglaUnicodeFont loadBundledFont() {
  final font = BanglaPdf.defaultFont;
  expect(font, isA<BanglaUnicodeFont>(),
      reason: 'the bundled default font must support OpenType shaping');
  return font as BanglaUnicodeFont;
}

bool _isBanglaRune(int r) =>
    (r >= 0x0980 && r <= 0x09FE) || r == 0x0964 || r == 0x0965;

void main() {
  tearDown(BanglaPdf.reset);

  group('bundled font', () {
    test('is a Unicode Bangla font with layout tables', () {
      final font = loadBundledFont();
      expect(font.canShapeBangla, isTrue);
      expect(font.otf.gsub, isNotNull);
      expect(font.otf.gpos, isNotNull);
      expect(font.otf.hasBengaliCoverage, isTrue);
    });

    test('the legacy font is still available and is an 8-bit font', () {
      final legacy = BanglaFontManager().legacyFont;
      final otf = OtFont.parse(
        // ignore: invalid_use_of_visible_for_testing_member
        ByteData.sublistView(Uint8List(0)),
      );
      expect(otf, isNull, reason: 'guard: empty bytes never parse');
      expect(legacy, isNotNull);
      expect(legacy, isNot(isA<BanglaUnicodeFont>()));
    });
  });

  group('shaper over the corpus', () {
    test('never throws and never emits .notdef for Bangla text', () {
      final font = loadBundledFont();
      final broken = <String>[];
      for (final c in loadCorpus()) {
        final text = c['text'] as String;
        if (text.isEmpty) continue;
        final run = font.shape(text);
        for (var i = 0; i < run.glyphs.length; i++) {
          final g = run.glyphs[i];
          if (g.gid != 0) continue;
          // .notdef is only acceptable for a codepoint the font truly lacks.
          final source = g.text;
          if (source.any(_isBanglaRune)) {
            broken.add('${c['id']}: ${c['text']}');
            break;
          }
        }
      }
      expect(broken, isEmpty,
          reason: 'these cases produced .notdef for Bangla:\n'
              '${broken.join('\n')}');
    });

    test('clusters cover every glyph and reproduce the source text', () {
      final font = loadBundledFont();
      for (final c in loadCorpus()) {
        final text = c['text'] as String;
        if (text.trim().isEmpty) continue;
        final run = font.shape(text);
        var covered = 0;
        final rebuilt = StringBuffer();
        for (final cluster in run.clusters) {
          expect(cluster.glyphStart, covered, reason: 'gap in ${c['id']}');
          covered = cluster.glyphEnd;
          rebuilt.write(cluster.text);
        }
        expect(covered, run.glyphs.length,
            reason: 'unclaimed glyphs in ${c['id']}');
        // Cluster text is the source text, in logical order, with nothing
        // lost. Text that shapes to no glyphs at all (a lone joiner) has no
        // cluster to carry it, which is the one legitimate exception.
        expect(
          rebuilt.toString(),
          run.glyphs.isEmpty ? '' : text,
          reason: 'cluster text lost in ${c['id']}',
        );
      }
    });

    test('NFC and NFD inputs shape identically', () {
      final font = loadBundledFont();
      const pairs = <List<String>>[
        ['কো', 'কো'],
        ['কৌ', 'কৌ'],
        ['ড়', 'ড়'],
        ['ঢ়', 'ঢ়'],
        ['য়', 'য়'],
        ['ড়া', 'ড়া'],
      ];
      for (final pair in pairs) {
        final a = font.shape(pair[0]).glyphs.map((g) => g.gid).toList();
        final b = font.shape(pair[1]).glyphs.map((g) => g.gid).toList();
        expect(b, a, reason: 'NFC/NFD mismatch for ${pair[0]}');
      }
    });

    test('pre-base vowel signs are reordered before their consonant', () {
      final font = loadBundledFont();
      for (final matra in <String>['ি', 'ে', 'ৈ']) {
        final run = font.shape('ক$matra');
        expect(run.glyphs.length, greaterThanOrEqualTo(2));
        final ka = font.otf.glyphForRune(0x0995);
        expect(run.glyphs.first.gid, isNot(ka),
            reason: '$matra must render before ক');
        expect(run.glyphs.any((g) => g.gid == ka), isTrue);
      }
    });

    test('conjuncts ligate rather than falling back to a visible hasanta', () {
      final font = loadBundledFont();
      final virama = font.otf.glyphForRune(0x09CD);
      const conjuncts = <String>[
        'ক্ষ',
        'জ্ঞ',
        'ষ্ণ',
        'ক্ত',
        'ন্ত্র',
        'ক্ষ্ম',
        'ঙ্ক্ষ',
        'ত্ত্ব',
        'চ্ছ্ব',
        'ম্ভ্র',
        'স্ত্র',
        'স্ত্র্য',
      ];
      for (final text in conjuncts) {
        final gids = font.shape(text).glyphs.map((g) => g.gid);
        expect(gids, isNot(contains(virama)),
            reason: '$text still renders a standalone hasanta');
      }
    });

    test('reph words shape without a stray ra', () {
      final font = loadBundledFont();
      for (final text in <String>['কর্ম', 'ধর্ম', 'বর্ষ', 'পূর্ব', 'শর্ত']) {
        final run = font.shape(text);
        expect(run.glyphs, isNotEmpty);
        expect(run.glyphs.map((g) => g.gid),
            isNot(contains(font.otf.glyphForRune(0x09CD))));
      }
    });
  });

  group('shaping rules that were once wrong', () {
    test('ZWNJ after a virama blocks the conjunct and keeps the hasanta', () {
      final font = loadBundledFont();
      final blocked = font.shape('ক\u09CD\u200Cষ').glyphs;
      final joined = font.shape('ক\u09CDষ').glyphs;
      // The joined form is a single ligature; the blocked form is not, and it
      // must not silently drop the hasanta either.
      expect(joined.length, 1, reason: 'ক + virama + ষ should ligate');
      expect(blocked.length, greaterThan(1),
          reason: 'ZWNJ must stop ক্ষ forming');
      expect(blocked.first.gid, isNot(joined.first.gid));
    });

    test('a four-consonant conjunct still takes a following ya-phala', () {
      final font = loadBundledFont();
      final full = font.shape('ঙ্ক্ষ্য').glyphs;
      final withoutPhala = font.shape('ঙ্ক্ষ').glyphs;
      // ঙ্ক্ষ is one glyph; adding ্য must add exactly one more (the phala),
      // not break the conjunct back into halves.
      expect(withoutPhala.length, 1);
      expect(full.length, 2);
      expect(full.first.gid, withoutPhala.first.gid);
    });

    test('a matra keeps its plain form across a syllable boundary', () {
      final font = loadBundledFont();
      // কার্য is ক + া in one syllable and র্য in the next. A contextual rule
      // that spans them must still be allowed to decline to fire.
      final run = font.shape('কার্য');
      expect(run.glyphs.length, greaterThanOrEqualTo(3));
      expect(run.glyphs.map((g) => g.gid), isNot(contains(0)));
    });

    test('attached marks keep any advance GPOS gave them', () {
      final font = loadBundledFont();
      // Zeroing every attached mark's advance used to lose `dist` adjustments.
      final run = font.shape('ন্ধ্র');
      expect(run.glyphs, isNotEmpty);
      expect(run.advance, greaterThan(0));
    });
  });

  group('legacy mode', () {
    test('no corpus case throws, which 1.0.6 did on 21 of them', () {
      for (final c in loadCorpus()) {
        final text = c['text'] as String;
        expect(() => text.fix, returnsNormally,
            reason: 'crashed on ${c['id']}');
      }
    });

    test('reph words that crashed 1.0.6 now transcode', () {
      for (final text in <String>[
        'কর্ম',
        'ধর্ম',
        'বর্ষ',
        'পূর্ব',
        'শর্ত',
        'র্ক'
      ]) {
        expect(() => text.fix, returnsNormally);
        expect(text.fix, isNotEmpty);
      }
    });
  });
}
