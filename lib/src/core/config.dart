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
/// other widgets shape Bangla correctly using the bundled Kalpurush.
class BanglaPdf {
  BanglaPdf._();

  static BanglaShapingMode _shapingMode = BanglaShapingMode.auto;
  static pw.Font? _defaultFont;
  static List<pw.Font> _fallbackFonts = const <pw.Font>[];

  /// Fonts consulted, in order, for characters the active font cannot draw.
  ///
  /// Empty by default. See [configure].
  static List<pw.Font> get fallbackFonts => _fallbackFonts;

  /// The active shaping mode. Defaults to [BanglaShapingMode.auto].
  static BanglaShapingMode get shapingMode => _shapingMode;

  /// Configures the package.
  ///
  /// [defaultFont] replaces the bundled Bangla font everywhere a widget is not
  /// given an explicit one. Either a font from [BanglaPdf.loadFont] or a plain
  /// `pw.Font.ttf` works: a `pw.Font.ttf` that covers Bengali is upgraded to a
  /// shaping font here, so callers do not have to know which to use. A legacy
  /// Bijoy face is kept as it is and drives the 1.0.x transcoding path.
  /// [fallbackFonts] are consulted, in order, for any character the active
  /// font has no glyph for — accented Latin, currency signs, arrows, emoji.
  /// It is the package-wide equivalent of `TextStyle.fontFallback`, which is
  /// also honoured and takes precedence.
  ///
  /// No Bangla font covers emoji or symbols, so supplying a fallback is the
  /// only way to render them. Pass an empty list to clear.
  static void configure({
    BanglaShapingMode? shapingMode,
    pw.Font? defaultFont,
    List<pw.Font>? fallbackFonts,
  }) {
    if (shapingMode != null) _shapingMode = shapingMode;
    if (defaultFont != null) _defaultFont = _promoteToShaping(defaultFont);
    if (fallbackFonts != null) _fallbackFonts = List<pw.Font>.of(fallbackFonts);
  }

  /// Re-reads a plain `pw.Font.ttf` as a shaping font when it can draw Bangla
  /// from Unicode. Anything else — a Bijoy face, a Latin font, a font already
  /// from [loadFont] — is returned unchanged.
  static pw.Font _promoteToShaping(pw.Font font) {
    if (font is BanglaUnicodeFont || font is! pw.TtfFont) return font;
    final promoted = BanglaUnicodeFont.tryParse(font.data);
    return promoted != null && promoted.canShapeBangla ? promoted : font;
  }

  /// Restores the shipped defaults. Mainly useful in tests.
  static void reset() {
    _shapingMode = BanglaShapingMode.auto;
    _defaultFont = null;
    _fallbackFonts = const <pw.Font>[];
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

  /// Fonts to consult, in order, for characters [style]'s font cannot draw.
  ///
  /// The style's own `fontFallback` comes first, then anything given to
  /// [configure]. Each is re-read as a shaping font so its glyph ids and
  /// advances are reachable; one that cannot be parsed is skipped rather than
  /// failing the layout. A fallback is exempt from the Bangla-coverage test
  /// that [resolveShapingFont] applies -- an emoji or Latin face covers no
  /// Bangla by definition, which is the whole point of it.
  static List<BanglaUnicodeFont> resolveFallbacks(pw.TextStyle? style) {
    final requested = <pw.Font>[
      ...?style?.fontFallback,
      ..._fallbackFonts,
    ];
    if (requested.isEmpty) return const <BanglaUnicodeFont>[];

    final out = <BanglaUnicodeFont>[];
    for (final font in requested) {
      if (font is BanglaUnicodeFont) {
        out.add(font);
        continue;
      }
      if (font is! pw.TtfFont) continue;
      final cached = _fallbackCache[font];
      if (cached is BanglaUnicodeFont) {
        out.add(cached);
        continue;
      }
      final parsed = BanglaUnicodeFont.tryParse(font.data);
      if (parsed == null) continue;
      _fallbackCache[font] = parsed;
      out.add(parsed);
    }
    return out;
  }

  /// Parsing a TTF is not free and `build` runs per layout pass.
  static final Expando<Object> _fallbackCache =
      Expando<Object>('banglaPdfFallback');

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
