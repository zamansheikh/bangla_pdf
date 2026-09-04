import 'dart:io';
import 'dart:typed_data';
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/shaping/bengali_categories.dart';
import 'package:bangla_pdf/src/shaping/bengali_shaper.dart';

void main(List<String> args) {
  final font =
      OtFont.parse(ByteData.sublistView(File(args[0]).readAsBytesSync()))!;
  final text = args[1];
  print(
      'input runes: ${text.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ')}');
  print('categories : ${text.runes.map((r) => categoryOf(r).name).join(' ')}');
  final run = BengaliShaper(font).shape(text);
  for (final g in run.glyphs) {
    print('  gid=${g.gid.toString().padLeft(4)} cluster=${g.cluster} '
        'syl=${g.syllable} pos=${g.position} adv=${g.xAdvance} '
        'off=(${g.xOffset},${g.yOffset}) text=${g.text.map((c) => c.toRadixString(16)).join(',')}');
  }
}
