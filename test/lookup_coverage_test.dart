// The OpenType lookup types this engine implements, and the evidence for them.
//
// Bengali fonts use a narrow slice of OpenType: across the five tested faces
// the types present are GSUB 1,2,3,4,5,6 and GPOS 1,2,4,6,8. The corpus
// exercises those to 234/234 against HarfBuzz. The two types added for
// completeness -- GSUB 8 and GPOS 3 -- appear in no Bengali font, so they are
// checked here against fonts that do use them.
import 'dart:io';

import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/shaping/bengali_shaper.dart';
import 'package:flutter_test/flutter_test.dart';

OtFont load(String name) => OtFont.parse(
      File('test/fixtures/fonts/$name').readAsBytesSync().buffer.asByteData(),
    )!;

Set<int> lookupTypes(OtFont font, LayoutTable? table) {
  if (table == null) return const <int>{};
  final types = <int>{};
  for (var i = 0; i < table.lookupCount; i++) {
    final offset = table.lookupOffset(i);
    if (offset != null) types.add(font.d.u16(offset));
  }
  return types;
}

void main() {
  test('GSUB type 8 matches HarfBuzz on a font that uses it', () {
    // Noto Sans Coptic puts a reverse chaining substitution in `ccmp`: a
    // combining overline takes a different form depending on what follows it.
    // Reverse chaining is the one substitution that must run right to left,
    // because each replacement depends on glyphs further right that have not
    // been substituted yet -- running it forwards silently gives other glyphs.
    final font = load('NotoSansCoptic-Regular.ttf');
    expect(lookupTypes(font, font.gsub), contains(8));

    final shaper = BengaliShaper(font);
    // Expected values are `hb-shape --no-glyph-names` on the same strings.
    const expected = <String, List<int>>{
      'ⲁ̅Ⲃ̅': <int>[34, 199, 35, 196],
      'ⲁ̅': <int>[34, 10],
      'ⲁ̿Ⲃ̿': <int>[34, 200, 35, 202],
    };
    for (final entry in expected.entries) {
      expect(
        shaper.shape(entry.key).glyphs.map((g) => g.gid).toList(),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('no Bengali font needs either of the two added types', () {
    // The claim that adding them changes nothing for Bangla, checked rather
    // than asserted. If a future font does use one, this fails and the corpus
    // numbers need re-measuring.
    for (final name in const <String>[
      'Kalpurush-Unicode.ttf',
      'NotoSansBengali-Regular.ttf',
      'NotoSerifBengali-Regular.ttf',
      'SolaimanLipi.ttf',
      'SiyamRupali.ttf',
    ]) {
      final font = load(name);
      expect(lookupTypes(font, font.gsub), isNot(contains(8)), reason: name);
      expect(lookupTypes(font, font.gpos), isNot(contains(3)), reason: name);
    }
  });

  test('the types Bengali fonts do use are all implemented', () {
    const gsubImplemented = <int>{1, 2, 3, 4, 5, 6, 7, 8};
    const gposImplemented = <int>{1, 2, 3, 4, 5, 6, 8, 9};
    for (final name in const <String>[
      'Kalpurush-Unicode.ttf',
      'NotoSansBengali-Regular.ttf',
      'NotoSerifBengali-Regular.ttf',
      'SolaimanLipi.ttf',
      'SiyamRupali.ttf',
    ]) {
      final font = load(name);
      expect(
        lookupTypes(font, font.gsub).difference(gsubImplemented),
        isEmpty,
        reason: '$name uses an unimplemented GSUB type',
      );
      expect(
        lookupTypes(font, font.gpos).difference(gposImplemented),
        isEmpty,
        reason: '$name uses an unimplemented GPOS type',
      );
    }
  });
}
