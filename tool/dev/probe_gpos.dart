import 'dart:io';
import 'dart:typed_data';
import 'package:bangla_pdf/src/ot/ot_font.dart';

void main(List<String> args) {
  final font =
      OtFont.parse(ByteData.sublistView(File(args[0]).readAsBytesSync()))!;
  final feats = font.gpos!.featureLookups(['bng2', 'beng']);
  for (final k in feats.keys.toList()..sort()) {
    print('$k -> ${feats[k]!.length} lookups ${feats[k]!.take(8).toList()}');
  }
}
