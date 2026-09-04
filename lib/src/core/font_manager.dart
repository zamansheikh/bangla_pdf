part of 'package:bangla_pdf/bangla_pdf.dart';

/// Singleton Font Manager for Bangla Fonts.
class BanglaFontManager {
  factory BanglaFontManager() => _instance;

  BanglaFontManager._internal();

  static final BanglaFontManager _instance = BanglaFontManager._internal();

  pw.Font? _defaultFont;
  pw.Font? _legacyFont;

  /// The default Bangla font: bundled Kalpurush (Unicode), shaped with its own
  /// OpenType tables.
  ///
  /// This is the same typeface 1.0.x used, so upgrading does not change how a
  /// document looks — only whether Bangla is shaped correctly.
  ///
  /// Before 1.1.0 this returned an 8-bit "Kalpurush ANSI" font that could only
  /// be used with text already transcoded to Bijoy. That font is still
  /// available as [legacyFont] and is selected automatically in
  /// [BanglaShapingMode.legacy].
  pw.Font get defaultFont => _defaultFont ??= BanglaUnicodeFont.tryParse(
        base64Decode(_bundledUnicodeFontBase64).buffer.asByteData(),
      ) ??
      legacyFont;

  /// The bundled legacy Bijoy/ANSI font (Kalpurush ANSI), used by
  /// [BanglaShapingMode.legacy].
  pw.Font get legacyFont => _legacyFont ??= pw.Font.ttf(
        base64Decode(_kalpurushBase64).buffer.asByteData(),
      );

  /// Function to load a TTF font from byte data and return the font family name
  static bool isBanglaText(String text) {
    // Regex for Bangla Unicode block
    final banglaRegex = RegExp(r'[\u0980-\u09FF]');
    return banglaRegex.hasMatch(text);
  }
}
