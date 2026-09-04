import 'dart:io';
import 'dart:typed_data';
import 'package:bangla_pdf/src/ot/gsub.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';

void main(List<String> args) {
  final font =
      OtFont.parse(ByteData.sublistView(File(args[0]).readAsBytesSync()))!;
  final feats = font.gsub!.featureLookups(['bng2', 'beng']);
  print('features found: ${(feats.keys.toList()..sort()).join(' ')}');
  print('blwf lookups: ${feats['blwf']}  pstf: ${feats['pstf']}');
  final gsub = GsubEngine(font, font.gsub!);
  final virama = font.glyphForRune(0x09CD);
  print('virama gid = $virama');
  const probes = {
    'র': 0x09B0,
    'য': 0x09AF,
    'ব': 0x09AC,
    'ত': 0x09A4,
    'ষ': 0x09B7,
    'ক': 0x0995,
    'ম': 0x09AE,
    'ণ': 0x09A3,
    'ধ': 0x09A7,
    'ন': 0x09A8,
    'স': 0x09B8,
    'ঙ': 0x0999,
  };
  for (final entry in probes.entries) {
    final g = font.glyphForRune(entry.value)!;
    bool any(String tag, List<int> seq) =>
        (feats[tag] ?? []).any((i) => gsub.wouldApply(seq, i));
    print('${entry.key} gid=$g  '
        'blwf[V,C]=${any('blwf', [virama!, g])} '
        'blwf[C,V]=${any('blwf', [g, virama])} '
        'pstf[V,C]=${any('pstf', [virama, g])} '
        'pstf[C,V]=${any('pstf', [g, virama])}');
  }
}
