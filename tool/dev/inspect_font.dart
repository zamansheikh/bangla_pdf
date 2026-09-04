import 'dart:io';
import 'dart:typed_data';
import 'package:bangla_pdf/src/ot/ot_font.dart';

void main(List<String> args) {
  for (final p in args) {
    final b = File(p).readAsBytesSync();
    final f = OtFont.parse(ByteData.sublistView(b));
    if (f == null) {
      print('$p: NOT PARSED');
      continue;
    }
    print('=== ${p.split('/').last}');
    print(
        '  upem=${f.unitsPerEm} numGlyphs=${f.numGlyphs} asc=${f.ascender} desc=${f.descender}');
    print(
        '  cmap entries=${f.cmap.length} bengali=${f.cmap.keys.where((c) => c >= 0x0980 && c <= 0x09FF).length}');
    print('  hasBengaliCoverage=${f.hasBengaliCoverage}');
    print(
        '  GSUB=${f.gsub != null ? '${f.gsub!.lookupCount} lookups' : 'none'}  GPOS=${f.gpos != null ? '${f.gpos!.lookupCount} lookups' : 'none'}');
    final feats = f.gsub?.featureLookups(['bng2', 'beng']);
    if (feats != null) {
      print('  GSUB features: ${(feats.keys.toList()..sort()).join(' ')}');
    }
    final ka = f.glyphForRune(0x0995);
    print(
        '  gid(ক)=$ka advance=${ka == null ? '-' : f.advance(ka)} class=${ka == null ? '-' : f.glyphClass(ka)}');
    final sign = f.glyphForRune(0x09BF);
    print('  gid(ি)=$sign isMark=${sign == null ? '-' : f.isMark(sign)}');
  }
}
