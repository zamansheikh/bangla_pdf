import 'dart:io';
import 'dart:typed_data';
import 'package:bangla_pdf/src/pdf/bangla_font.dart';

void main(List<String> args) {
  for (final p in args) {
    final f = BanglaUnicodeFont.tryParse(
      ByteData.sublistView(File(p).readAsBytesSync()),
    );
    final name = p.split('/').last;
    if (f == null) {
      print('${name.padRight(30)} not a usable font');
      continue;
    }
    print('${name.padRight(30)} bengaliCoverage=${f.otf.hasBengaliCoverage} '
        'canShapeBangla=${f.canShapeBangla} '
        'gsub=${f.otf.gsub != null} '
        'bng2=${f.otf.gsub?.hasScript('bng2') ?? false} '
        'beng=${f.otf.gsub?.hasScript('beng') ?? false}');
  }
}
