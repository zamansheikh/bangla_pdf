// Development tool: shapes strings with the package's own engine and prints
// them in `hb-shape`'s format so the two can be diffed directly.
//
// Usage: dart run tool/dev/shape_dump.dart <font.ttf> < strings.txt
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/shaping/bengali_shaper.dart';

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final font = OtFont.parse(ByteData.sublistView(bytes));
  if (font == null) {
    stderr.writeln('could not parse ${args[0]}');
    exit(1);
  }
  final shaper = BengaliShaper(font);

  for (final line in const LineSplitter().convert(stdin.readAsStringSync())) {
    if (line.isEmpty) {
      stdout.writeln('[]');
      continue;
    }
    final run = shaper.shape(line);
    final parts = <String>[];
    for (final g in run.glyphs) {
      final buf = StringBuffer('${g.gid}=${g.cluster}');
      if (g.xOffset != 0 || g.yOffset != 0) {
        buf.write('@${g.xOffset},${g.yOffset}');
      }
      buf.write('+${g.xAdvance}');
      parts.add(buf.toString());
    }
    stdout.writeln('[${parts.join('|')}]');
  }
}

extension on Stdin {
  String readAsStringSync() {
    final out = StringBuffer();
    String? line;
    while ((line = readLineSync(encoding: utf8)) != null) {
      out.writeln(line);
    }
    return out.toString();
  }
}
