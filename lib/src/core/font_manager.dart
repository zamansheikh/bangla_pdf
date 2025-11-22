part of 'package:bangla_pdf/bangla_pdf.dart';

/// Singleton Font Manager for Bangla Fonts.
class BanglaFontManager {
  factory BanglaFontManager() => _instance;

  BanglaFontManager._internal() {
    // Load default font (Kalpurush) immediately from embedded data
    _defaultFont = pw.Font.ttf(
      base64Decode(_kalpurushBase64).buffer.asByteData(),
    );
  }

  static final BanglaFontManager _instance = BanglaFontManager._internal();

  late final pw.Font _defaultFont;

  /// Get the default Bangla font (Kalpurush)
  pw.Font get defaultFont => _defaultFont;

  /// Function to load a TTF font from byte data and return the font family name
  static bool isBanglaText(String text) {
    // Regex for Bangla Unicode block
    final banglaRegex = RegExp(r'[\u0980-\u09FF]');
    return banglaRegex.hasMatch(text);
  }
}
