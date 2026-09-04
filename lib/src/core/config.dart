part of 'package:bangla_pdf/bangla_pdf.dart';

/// How Bangla text is turned into glyphs.
enum BanglaShapingMode {
  /// Shape with the font's own OpenType tables when the font is a Unicode
  /// Bangla font; fall back to [legacy] for a legacy 8-bit font. This is the
  /// default and needs no configuration.
  auto,

  /// Always shape with the OpenType engine. Throws nothing, but a font with no
  /// Bengali coverage will render its `.notdef` glyph rather than silently
  /// producing Bijoy output.
  unicode,

  /// The 1.0.x pipeline: transcode Unicode to Bijoy ANSI and render with an
  /// 8-bit font. Kept for users who supply their own ANSI font (SutonnyMJ and
  /// friends) and need byte-identical output.
  legacy,
}

/// Package-wide configuration.
///
/// Everything here is optional: with no configuration at all, [Text] and the
/// other widgets shape Bangla correctly using the bundled Noto Sans Bengali.
class BanglaPdf {
  BanglaPdf._();

  static BanglaShapingMode _shapingMode = BanglaShapingMode.auto;
  static pw.Font? _defaultFont;

  /// The active shaping mode. Defaults to [BanglaShapingMode.auto].
  static BanglaShapingMode get shapingMode => _shapingMode;

  /// Configures the package.
  ///
  /// [defaultFont] replaces the bundled Bangla font everywhere a widget is not
  /// given an explicit one. Pass a font created with [BanglaPdf.loadFont] to
  /// keep OpenType shaping; a `pw.Font.ttf` is treated as a legacy 8-bit font.
  static void configure({
    BanglaShapingMode? shapingMode,
    pw.Font? defaultFont,
  }) {
    if (shapingMode != null) _shapingMode = shapingMode;
    if (defaultFont != null) _defaultFont = defaultFont;
  }

  /// Restores the shipped defaults. Mainly useful in tests.
  static void reset() {
    _shapingMode = BanglaShapingMode.auto;
    _defaultFont = null;
  }

  /// Loads a Unicode Bangla font for the shaping pipeline.
  ///
  /// Returns `null` if the bytes are not a usable font. Unlike `pw.Font.ttf`,
  /// the result can draw conjunct glyphs that no codepoint maps to, and writes
  /// a `/ToUnicode` CMap that copies back as the original Unicode.
  static pw.Font? loadFont(ByteData data) => BanglaUnicodeFont.tryParse(data);

  /// The font used when a widget is given none.
  static pw.Font get defaultFont =>
      _defaultFont ??
      (_shapingMode == BanglaShapingMode.legacy
          ? BanglaFontManager().legacyFont
          : BanglaFontManager().defaultFont);

  /// Resolves the font a widget should shape with.
  ///
  /// Returns `null` when the caller should fall back to the legacy ANSI path:
  /// either [BanglaShapingMode.legacy] is selected, or the supplied font is a
  /// legacy 8-bit font with no Bengali coverage.
  static BanglaUnicodeFont? resolveShapingFont(pw.Font? requested) {
    if (_shapingMode == BanglaShapingMode.legacy) return null;
    final font = requested ?? defaultFont;
    if (font is! BanglaUnicodeFont) return null;
    if (_shapingMode == BanglaShapingMode.unicode) return font;
    // auto: only take the Unicode path if this font really covers Bangla.
    return font.canShapeBangla ? font : null;
  }

  /// Whether [font] can draw every rune of [text].
  ///
  /// Only meaningful for a font from [loadFont]; a legacy 8-bit font always
  /// reports `false` for Bangla and is handled by the legacy path instead.
  static bool covers(pw.Font? font, String text) {
    final resolved = resolveShapingFont(font);
    if (resolved == null) return false;
    return text.runes.every(
      (r) => r == 0x20 || resolved.otf.glyphForRune(r) != null,
    );
  }
}

/// Shapes this string for PDF output with [font].
///
/// Advanced escape hatch for callers building their own PDF content. Returns
/// `null` when [font] is not a Unicode Bangla font.
extension BanglaShapeForPdf on String {
  /// Shapes the string, returning glyphs in visual order with their advances,
  /// offsets and the source text each cluster came from.
  ShapedRun? shapeForPdf(pw.Font font) =>
      font is BanglaUnicodeFont ? font.shape(this) : null;
}
