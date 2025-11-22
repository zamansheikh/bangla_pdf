part of 'package:bangla_pdf/bangla_pdf.dart';

extension BanglaTextExtension on String {
  bool get isBanglaText => BanglaFontManager.isBanglaText(this);

  /// Fixes the Bangla text by mapping it to ANSI (if Bangla).
  String get fix => isBanglaText ? BanglaUnicodeMapper.encodeANSI(this) : this;
}
