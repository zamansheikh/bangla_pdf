// Checks that cutting a font down to the glyphs a document draws leaves the
// document itself unchanged.
//
// Size is the easy half. The half that matters is that every glyph still has
// an outline afterwards: a subset that dropped one would still extract
// perfectly, because `/ActualText` carries the source text either way, and
// would simply render a blank where a conjunct used to be.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:bangla_pdf/extract.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/pdf/font_subset.dart';
import 'package:bangla_pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

ByteData fixture(String name) =>
    File('test/fixtures/fonts/$name').readAsBytesSync().buffer.asByteData();

String flatten(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

/// Text exercising conjuncts, reph, matras, digits and currency.
const sample =
    'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার — ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য '
    'কর্ম ধর্ম বর্ষ পূর্ব শর্ত কি কে কো ৳১২,৫০০.০০ Invoice #1042';

Future<Uint8List> render(String text) {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(build: (context) => pw.Text(text)));
  return pdf.save();
}

void main() {
  tearDown(BanglaPdf.reset);

  group('the subsetter itself', () {
    test('keeps every requested glyph and drops the rest', () {
      final source = fixture('Kalpurush-Unicode.ttf');
      final full = OtFont.parse(source)!;

      // A realistic working set: whatever shaping the sample needs.
      final font = BanglaPdf.defaultFont;
      final used = <int>{
        for (final glyph in sample.shapeForPdf(font)!.glyphs) glyph.gid,
      };
      expect(used.length, greaterThan(20));

      final subset = subsetTrueType(source, used);
      expect(subset, isNotNull);

      final cut = OtFont.parse(ByteData.sublistView(subset!))!;
      for (final gid in used) {
        final before = full.glyphExtents(gid);
        if (before == null) continue; // a space has no outline either way
        expect(
          cut.glyphExtents(gid),
          before,
          reason: 'glyph $gid lost its outline',
        );
      }
    });

    test('a composite glyph keeps the glyphs it is built from', () {
      final source = fixture('Kalpurush-Unicode.ttf');
      final full = OtFont.parse(source)!;
      final composites = findComposites(source);
      if (composites.isEmpty) {
        markTestSkipped('this font has no composite glyphs');
        return;
      }

      // Ask for the composite alone. Its components are not in the request, so
      // only the transitive walk can save them -- and without them the glyph
      // renders as a blank.
      final (composite, components) = composites.first;
      final subset = subsetTrueType(source, <int>{composite})!;
      final cut = OtFont.parse(ByteData.sublistView(subset))!;

      expect(cut.glyphExtents(composite), full.glyphExtents(composite));
      for (final part in components) {
        expect(
          cut.glyphExtents(part),
          full.glyphExtents(part),
          reason: 'component $part of composite $composite was dropped',
        );
      }
    });

    test('a font it cannot cut is refused rather than corrupted', () {
      // Not an sfnt at all.
      expect(
        subsetTrueType(
          ByteData.sublistView(Uint8List.fromList(<int>[1, 2, 3, 4])),
          <int>{1},
        ),
        isNull,
      );
      // A truncated directory.
      final truncated = Uint8List(64)
        ..[0] = 0
        ..[1] = 1
        ..[2] = 0
        ..[3] = 0
        ..[4] = 0xFF
        ..[5] = 0xFF;
      expect(
        subsetTrueType(ByteData.sublistView(truncated), <int>{1}),
        isNull,
      );
    });
  });

  group('documents', () {
    test('a page is a fraction of the font it draws from', () async {
      final bytes = await render(sample);
      final fontSize = fixture('Kalpurush-Unicode.ttf').lengthInBytes;
      // The whole 307 KB font used to go in; the page should now be a small
      // fraction of it, and still carry the font rather than reference it.
      expect(bytes.length, lessThan(fontSize ~/ 8));
      expect(latin1.decode(bytes, allowInvalid: true), contains('FontFile2'));
    });

    test('the text still comes back exactly', () async {
      final result = BanglaPdfExtractor.extract(await render(sample));
      expect(flatten(result.text), flatten(sample));
      expect(result.encodingDetected, BanglaTextEncoding.unicode);
    });

    test('a fallback font is cut down too', () async {
      BanglaPdf.configure(
        fallbackFonts: <pw.Font>[pw.Font.ttf(fixture('SolaimanLipi.ttf'))],
      );
      final bytes = await render('$sample café ± 50°C');
      // Two whole fonts would be over 400 KB.
      expect(bytes.length, lessThan(64 * 1024));
      expect(
        flatten(BanglaPdfExtractor.extract(bytes).text),
        flatten('$sample café ± 50°C'),
      );
    });

    test('every corpus case survives being subset', () async {
      // The corpus is the widest set of shaping this package handles, so it is
      // the strongest check that no outline goes missing.
      final cases = corpusCases()
          .map((c) => c['text'] as String)
          .where((t) => t.trim().isNotEmpty)
          .toList();
      expect(cases.length, greaterThan(200));

      final joined = cases.join('\n');
      final result = BanglaPdfExtractor.extract(await render(joined));
      // Every case's text is present, so every glyph it needed was kept.
      for (final text in cases) {
        expect(flatten(result.text), contains(flatten(text)));
      }
    });
  });
}

List<Map<String, dynamic>> corpusCases() =>
    (jsonDecode(File('test/corpus/bangla_cases.json').readAsStringSync())
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

/// Composite glyphs in [source], each with the glyph ids it is built from.
///
/// Read straight from `glyf` so the test does not depend on the code it is
/// checking.
List<(int, List<int>)> findComposites(ByteData d) {
  final count = d.getUint16(4);
  final tables = <String, (int, int)>{};
  for (var i = 0; i < count; i++) {
    final row = 12 + i * 16;
    final tag = String.fromCharCodes(<int>[
      for (var k = 0; k < 4; k++) d.getUint8(row + k),
    ]);
    tables[tag] = (d.getUint32(row + 8), d.getUint32(row + 12));
  }
  final head = tables['head']!.$1;
  final maxp = tables['maxp']!.$1;
  final loca = tables['loca']!.$1;
  final glyf = tables['glyf']!.$1;
  final numGlyphs = d.getUint16(maxp + 4);
  final long = d.getInt16(head + 50) != 0;

  int offsetAt(int i) =>
      long ? d.getUint32(loca + i * 4) : d.getUint16(loca + i * 2) * 2;

  final out = <(int, List<int>)>[];
  for (var gid = 0; gid < numGlyphs && out.length < 4; gid++) {
    final start = offsetAt(gid);
    if (offsetAt(gid + 1) <= start) continue;
    final at = glyf + start;
    if (at + 10 > d.lengthInBytes || d.getInt16(at) >= 0) continue;

    final parts = <int>[];
    var p = at + 10;
    while (p + 4 <= d.lengthInBytes) {
      final flags = d.getUint16(p);
      parts.add(d.getUint16(p + 2));
      p += 4 + ((flags & 0x0001) != 0 ? 4 : 2);
      if ((flags & 0x0008) != 0) {
        p += 2;
      } else if ((flags & 0x0040) != 0) {
        p += 4;
      } else if ((flags & 0x0080) != 0) {
        p += 8;
      }
      if ((flags & 0x0020) == 0) break;
    }
    if (parts.isNotEmpty) out.add((gid, parts));
  }
  return out;
}
