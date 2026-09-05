/// Shared plumbing for the `package:pdf` compatibility layer.
///
/// Nothing here is exported: `package:bangla_pdf/widgets.dart` re-exports only
/// the replacement widgets, so these helpers stay private to the package.
library;

import 'package:bangla_pdf/bangla_pdf.dart' as bp;
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/src/widgets/shaped_text.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Whether [text] contains anything from the Bengali block.
bool containsBangla(String text) => bp.BanglaFontManager.isBanglaText(text);

/// How a font named in a [pw.TextStyle] relates to Bangla.
enum _FontKind {
  /// Draws Bangla from Unicode codepoints: shape with it.
  unicodeBangla,

  /// Draws Bangla from Latin-1 byte values: a Bijoy face, so take the legacy
  /// transcoding path and leave the font alone.
  legacyBangla,

  /// Has nothing to do with Bangla — Helvetica, Roboto and every other Latin
  /// face. Bangla in a run styled with one of these gets the bundled font.
  other,
}

/// Parsing a TTF is not free and [pw.Widget.build] runs per widget per layout
/// pass, so each font is classified once.
final Expando<Object> _fontKindCache = Expando<Object>('banglaPdfFontKind');

_FontKind _classify(pw.Font font) {
  final cached = _fontKindCache[font];
  if (cached is _FontKind) return cached;

  final kind = _computeKind(font);
  _fontKindCache[font] = kind;
  return kind;
}

_FontKind _computeKind(pw.Font font) {
  if (font is BanglaUnicodeFont) return _FontKind.unicodeBangla;
  if (font is! pw.TtfFont) return _FontKind.other;

  final otf = OtFont.parse(font.data);
  if (otf == null) return _FontKind.other;
  if (otf.hasBengaliCoverage) return _FontKind.unicodeBangla;

  // No Bengali in the cmap, yet the Latin-1 supplement is densely covered:
  // that is a Bijoy face, which reaches its Bangla glyphs through high byte
  // values. A Latin text font has no reason to cover that range so heavily.
  // The same test identifies Bijoy documents in `package:bangla_pdf/extract.dart`.
  final high = otf.cmap.keys.where((c) => c >= 0xA0 && c <= 0xFF).length;
  return high >= 60 ? _FontKind.legacyBangla : _FontKind.other;
}

/// The font a run styled with [style] should shape Bangla with.
///
/// Returns `null` when the run must not be shaped, which is the signal to fall
/// back to the legacy Bijoy path.
///
/// The rules, in order:
///
/// 1. A font from [bp.BanglaPdf.loadFont] shapes with itself.
/// 2. A plain `pw.Font.ttf` that covers Bengali is promoted to a shaping font,
///    so naming a Bangla TTF through an ordinary [pw.TextStyle] works without
///    the caller having to know about `loadFont`.
/// 3. A legacy Bijoy face is honoured as chosen: shaping declines so the run
///    is transcoded and drawn with that font.
/// 4. Anything else — Helvetica, a Latin theme font, no font at all — leaves
///    Bangla to the configured default, so it still renders.
BanglaUnicodeFont? shapingFontFor(pw.TextStyle? style) {
  final requested = style?.font;

  if (requested != null) {
    switch (_classify(requested)) {
      case _FontKind.unicodeBangla:
        final shaped =
            bp.BanglaPdf.resolveShapingFont(requested) ?? _promoted(requested);
        if (shaped != null) return shaped;
      case _FontKind.legacyBangla:
        return null;
      case _FontKind.other:
        break;
    }
  }

  return bp.BanglaPdf.resolveShapingFont(null);
}

/// Re-reads a plain [pw.TtfFont] as a shaping font, once per font object.
final Expando<Object> _promotedCache = Expando<Object>('banglaPdfPromoted');

BanglaUnicodeFont? _promoted(pw.Font font) {
  if (font is! pw.TtfFont) return null;
  final cached = _promotedCache[font];
  if (cached is BanglaUnicodeFont) return cached;

  final promoted = bp.BanglaPdf.loadFont(font.data);
  if (promoted is! BanglaUnicodeFont) return null;
  // Respect the configured mode: `legacy` must stay legacy even here.
  if (bp.BanglaPdf.resolveShapingFont(promoted) == null) return null;
  _promotedCache[font] = promoted;
  return promoted;
}

/// A leaf of a flattened [pw.InlineSpan] tree.
class SpanRun {
  const SpanRun(this.text, this.style);

  /// The run's text, in logical order.
  final String text;

  /// The style inherited from every ancestor span, already merged.
  final pw.TextStyle style;
}

/// Flattens [span] into its text leaves, merging styles from the root down.
///
/// [pw.WidgetSpan]s are dropped: they carry a widget rather than text, and the
/// shaped path lays runs out as separate widgets anyway.
List<SpanRun> flattenSpans(pw.InlineSpan span, pw.TextStyle inherited) {
  final merged = inherited.merge(span.style);
  final out = <SpanRun>[];
  if (span is pw.TextSpan) {
    final text = span.text;
    if (text != null && text.isNotEmpty) out.add(SpanRun(text, merged));
    for (final child in span.children ?? const <pw.InlineSpan>[]) {
      out.addAll(flattenSpans(child, merged));
    }
  }
  return out;
}

/// Draws [text], shaping Bangla when it can and deferring to
/// `package:pdf` when it cannot.
///
/// This is the single decision point for the whole compatibility layer. A
/// string with no Bengali in it is handed to [pw.Text] untouched, so a document
/// with no Bangla renders exactly as it would without this package.
class BanglaAwareText extends pw.StatelessWidget {
  /// Creates a [BanglaAwareText].
  BanglaAwareText(
    this.text, {
    this.style,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.maxLines,
    this.overflow,
  });

  /// The text to draw, in logical order.
  final String text;

  /// Style for the run, merged over the ambient theme.
  final pw.TextStyle? style;

  /// Horizontal alignment.
  final pw.TextAlign? textAlign;

  /// Reading direction, honoured on the `package:pdf` path.
  final pw.TextDirection? textDirection;

  /// Whether text breaks at soft line breaks.
  final bool? softWrap;

  /// Whether the box hugs the text.
  final bool tightBounds;

  /// Multiplier applied to the font size.
  final double textScaleFactor;

  /// Maximum number of lines before overflowing.
  final int? maxLines;

  /// How overflow is handled.
  final pw.TextOverflow? overflow;

  @override
  pw.Widget build(pw.Context context) {
    final resolved = pw.Theme.of(context).defaultTextStyle.merge(style);

    // No Bangla: hand it to package:pdf untouched, so a document without any
    // Bangla in it renders exactly as it would without this package.
    if (!containsBangla(text)) {
      return pw.Text(
        text,
        style: style,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        tightBounds: tightBounds,
        textScaleFactor: textScaleFactor,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final font = shapingFontFor(resolved);
    if (font == null) {
      // Bangla, but shaping declined: BanglaShapingMode.legacy is selected, or
      // the caller supplied a legacy 8-bit font. Take the 1.0.x Bijoy path
      // rather than pw.Text, which would draw the raw Unicode as tofu.
      return pw.RichText(
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        tightBounds: tightBounds,
        textScaleFactor: textScaleFactor,
        maxLines: maxLines,
        overflow: overflow ?? pw.TextOverflow.visible,
        text: pw.TextSpan(
          children: bp.FixingUtils.getAutoLocalizedSpans(
            text: text,
            banglaFont: style?.font,
            fontSize: resolved.fontSize ?? 12,
            color: resolved.color ?? PdfColors.black,
            style: style,
          ),
        ),
      );
    }

    return ShapedTextWidget(
      text: text,
      font: font,
      fontSize: (resolved.fontSize ?? 12) * textScaleFactor,
      color: resolved.color ?? PdfColors.black,
      textAlign: textAlign ?? pw.TextAlign.start,
      maxLines: maxLines,
      // `TextStyle.lineSpacing` is extra leading in points in `package:pdf`,
      // and pw's own default for it is 0 -- feeding it to the multiplier would
      // collapse every line to zero height.
      extraLeading: resolved.lineSpacing ?? 0,
      letterSpacing: resolved.letterSpacing ?? 0,
      // pw.RichText spans pages only when its overflow is `span`; matching
      // that keeps MultiPage behaving identically for Bangla and Latin.
      canSpanPages: overflow == pw.TextOverflow.span,
      fallbackFonts: bp.BanglaPdf.resolveFallbacks(resolved),
      softWrap: softWrap ?? true,
      tightBounds: tightBounds,
      textDirection: textDirection ?? pw.Directionality.of(context),
    );
  }
}
