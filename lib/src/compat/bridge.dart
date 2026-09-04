/// Shared plumbing for the `package:pdf` compatibility layer.
///
/// Nothing here is exported: `package:bangla_pdf/widgets.dart` re-exports only
/// the replacement widgets, so these helpers stay private to the package.
library;

import 'package:bangla_pdf/bangla_pdf.dart' as bp;
import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/src/widgets/shaped_text.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Whether [text] contains anything from the Bengali block.
bool containsBangla(String text) => bp.BanglaFontManager.isBanglaText(text);

/// The font a run styled with [style] should shape Bangla with.
///
/// The style's own font wins when it can shape — that is how a caller picks a
/// different Bangla typeface through an ordinary [pw.TextStyle]. Otherwise the
/// configured default is used, so Bangla still renders when the surrounding
/// theme names a Latin-only font. Returns `null` when nothing can shape, which
/// is the signal to stay on `package:pdf`'s own text path.
BanglaUnicodeFont? shapingFontFor(pw.TextStyle? style) =>
    bp.BanglaPdf.resolveShapingFont(style?.font) ??
    bp.BanglaPdf.resolveShapingFont(null);

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
      lineSpacing: resolved.lineSpacing ?? 1.2,
      letterSpacing: resolved.letterSpacing ?? 0,
    );
  }
}
