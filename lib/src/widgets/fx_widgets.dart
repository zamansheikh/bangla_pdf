part of 'package:bangla_pdf/bangla_pdf.dart';

/// Text with Bangla shaped correctly.
///
/// A drop-in replacement for [pw.Text]: it accepts the same parameters and
/// adds Bangla handling. Mixed Bangla, Latin, digits and punctuation are laid
/// out in one pass by one font, so nothing needs splitting up by hand.
class Text extends pw.StatelessWidget {
  /// The text to draw, in logical order.
  final String text;

  /// Font size. Ignored when [style] or [banglaStyle] sets one.
  final double fontSize;

  /// Font weight.
  final pw.FontWeight fontWeight;

  /// Fill colour.
  final PdfColor color;

  /// Horizontal alignment.
  final pw.TextAlign? textAlign;

  /// Reading direction.
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

  /// Word-breaking callback, as in [pw.RichText.hyphenation].
  ///
  /// Applies to the legacy path only: the shaping pipeline breaks on syllable
  /// boundaries so a line never splits inside a conjunct.
  final pw.Hyphenation? hyphenation;

  /// The font to use for Bangla.
  ///
  /// Defaults to the bundled Kalpurush, shaped with its own OpenType tables.
  /// Pass a font from [BanglaPdf.loadFont] to use a different Unicode font; a
  /// legacy Bijoy font is detected and takes the 1.0.x path instead.
  final pw.Font? banglaFont;

  /// The font for non-Bangla runs, used only on the legacy Bijoy path.
  ///
  /// The shaping pipeline draws the whole string with one font, because a
  /// Unicode Bangla font covers Latin and digits too.
  final pw.Font? generalFont;

  /// Style for the text. On the legacy path this applies to non-Bangla runs.
  final pw.TextStyle? style;

  /// Style for Bangla. Takes precedence over [style] when both are given.
  final pw.TextStyle? banglaStyle;

  /// Creates a [Text].
  Text(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.maxLines,
    this.overflow,
    this.hyphenation,
    this.banglaFont,
    this.generalFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    // Prefer real OpenType shaping. It only declines when the caller supplied
    // a legacy 8-bit font or asked for BanglaShapingMode.legacy, in which case
    // the 1.0.x Bijoy pipeline below runs unchanged.
    final shapingFont = BanglaPdf.resolveShapingFont(
      banglaFont ?? banglaStyle?.font,
    );
    if (shapingFont != null) {
      final effective = banglaStyle ?? style;
      return ShapedTextWidget(
        text: text,
        font: shapingFont,
        fontSize: (effective?.fontSize ?? fontSize) * textScaleFactor,
        color: effective?.color ?? color,
        textAlign: textAlign ?? pw.TextAlign.start,
        maxLines: maxLines,
        lineSpacing: effective?.lineSpacing ?? 1.2,
        // Opt-in, as in package:pdf: only `span` lets a MultiPage break the
        // text across pages, so existing callers see no change.
        canSpanPages: overflow == pw.TextOverflow.span,
        fallbackFonts: BanglaPdf.resolveFallbacks(effective),
        softWrap: softWrap ?? true,
        tightBounds: tightBounds,
        textDirection: textDirection ?? pw.TextDirection.ltr,
      );
    }

    return pw.RichText(
      textAlign: textAlign ?? pw.TextAlign.start,
      textDirection: textDirection,
      softWrap: softWrap,
      tightBounds: tightBounds,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      overflow: overflow ?? pw.TextOverflow.visible,
      hyphenation: hyphenation,
      text: pw.TextSpan(
        children: FixingUtils.getAutoLocalizedSpans(
          text: text,
          banglaFont: banglaFont,
          generalFont: generalFont,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          style: style,
          banglaStyle: banglaStyle,
        ),
      ),
    );
  }
}

/// Text that splits Bangla from non-Bangla and fonts each part separately.
///
/// Kept for source compatibility. [Text] does everything this does and nothing
/// less: since 1.1.0 a Unicode Bangla font covers Latin and digits, so there is
/// no longer anything to split.
@Deprecated('Use Text instead; it is identical. Will be removed in 2.0.0.')
class AutoText extends Text {
  /// Creates an [AutoText].
  @Deprecated('Use Text instead; it is identical. Will be removed in 2.0.0.')
  AutoText(
    super.text, {
    super.fontSize,
    super.fontWeight,
    super.color,
    super.textAlign = pw.TextAlign.start,
    super.textDirection,
    super.softWrap,
    super.tightBounds,
    super.textScaleFactor,
    super.maxLines,
    super.overflow,
    super.hyphenation,
    super.banglaFont,
    super.generalFont,
    super.style,
    super.banglaStyle,
  });
}

/// A text span descriptor that nothing in this package has ever consumed.
///
/// Kept only so an existing import keeps compiling. Use [TextSpan] with
/// [RichText].
@Deprecated('Unused since 1.0. Use TextSpan instead. Removed in 2.0.0.')
class RichTextItem {
  final String text;
  final double fontSize;
  final PdfColor color;
  final pw.Font? banglaFont;

  @Deprecated('Unused since 1.0. Use TextSpan instead. Removed in 2.0.0.')
  const RichTextItem({
    required this.text,
    this.fontSize = 14,
    this.color = PdfColors.black,
    this.banglaFont,
  });
}

/// Rich text with per-span styling, with Bangla shaped correctly.
///
/// Takes the same layout parameters as [pw.RichText]; the difference is that
/// spans are given as a `List<TextSpan>` rather than a single tree, because
/// each Bangla span is laid out by its own shaper.
class RichText extends pw.StatelessWidget {
  /// The spans to lay out, in order.
  final List<TextSpan> spans;

  /// Horizontal alignment.
  final pw.TextAlign textAlign;

  /// Reading direction.
  final pw.TextDirection? textDirection;

  /// Whether text breaks at soft line breaks.
  final bool? softWrap;

  /// Whether the box hugs the text.
  final bool tightBounds;

  /// Multiplier applied to every font size.
  final double textScaleFactor;

  /// Maximum number of lines before overflowing.
  final int? maxLines;

  /// How overflow is handled.
  final pw.TextOverflow? overflow;

  /// Word-breaking callback, as in [pw.RichText.hyphenation].
  final pw.Hyphenation? hyphenation;

  /// Creates a [RichText].
  RichText({
    required this.spans,
    this.textAlign = pw.TextAlign.start,
    this.textDirection,
    this.softWrap,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.maxLines,
    this.overflow,
    this.hyphenation,
  });

  @override
  pw.Widget build(pw.Context context) {
    // Under the shaping pipeline each span is laid out by its own widget, so
    // they are flowed with a Wrap rather than merged into one pw.TextSpan.
    if (BanglaPdf.resolveShapingFont(null) != null ||
        spans.any((s) => BanglaPdf.resolveShapingFont(s.banglaFont) != null)) {
      return pw.Wrap(
        crossAxisAlignment: pw.WrapCrossAlignment.end,
        children: spans
            .map(
              (span) => Text(
                span.text,
                banglaFont: span.banglaFont,
                fontSize: span.effectiveFontSize,
                fontWeight: span.effectiveFontWeight,
                color: span.effectiveColor,
                textAlign: textAlign,
                style: span.style,
              ),
            )
            .toList(),
      );
    }

    final List<pw.InlineSpan> children = [];

    for (final span in spans) {
      children.addAll(FixingUtils.getAutoLocalizedSpans(
        text: span.text,
        banglaFont: span.banglaFont,
        fontSize: span.effectiveFontSize,
        fontWeight: span.effectiveFontWeight,
        color: span.effectiveColor,
        style: span.style,
        baseline: span.baseline,
        annotation: span.annotation,
      ));
    }

    return pw.RichText(
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      tightBounds: tightBounds,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      overflow: overflow ?? pw.TextOverflow.visible,
      hyphenation: hyphenation,
      text: pw.TextSpan(children: children),
    );
  }
}

/// One span inside a [RichText].
///
/// The text is positional, as it has been since 1.0; everything else mirrors
/// [pw.TextSpan] plus the Bangla-specific font override.
class TextSpan {
  /// The span's text.
  final String text;

  /// Font size. Ignored when [style] sets one.
  final double fontSize;

  /// Font weight.
  final pw.FontWeight fontWeight;

  /// Fill colour. Ignored when [style] sets one.
  final PdfColor color;

  /// Style applied to this span, matching [pw.TextSpan.style].
  final pw.TextStyle? style;

  /// Vertical shift from the baseline, as in [pw.TextSpan.baseline].
  final double baseline;

  /// Link or annotation attached to this span.
  final pw.AnnotationBuilder? annotation;

  /// The font to use for Bangla runs in this span.
  final pw.Font? banglaFont;

  /// Creates a [TextSpan].
  TextSpan(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.style,
    this.baseline = 0,
    this.annotation,
    this.banglaFont,
  });

  /// The effective size, preferring [style].
  double get effectiveFontSize => style?.fontSize ?? fontSize;

  /// The effective colour, preferring [style].
  PdfColor get effectiveColor => style?.color ?? color;

  /// The effective weight, preferring [style].
  pw.FontWeight get effectiveFontWeight => style?.fontWeight ?? fontWeight;
}

/// A heading, with Bangla shaped correctly.
///
/// Takes everything [pw.Header] takes, so it is a drop-in replacement. The one
/// difference is that the text is positional here rather than named, which is
/// the shape this package has had since 1.0.
class Header extends pw.StatelessWidget {
  /// The heading text.
  final String text;

  /// Content to place instead of [text], as in [pw.Header.child].
  final pw.Widget? child;

  /// Font size. Ignored when [textStyle] or [banglaStyle] sets one.
  final double fontSize;

  /// Font weight.
  final pw.FontWeight fontWeight;

  /// Heading level, 0 to 5, as in [pw.Header].
  final int level;

  /// Outline title; defaults to [text].
  final String? title;

  /// Space outside the heading.
  final pw.EdgeInsetsGeometry? margin;

  /// Space inside the heading.
  final pw.EdgeInsetsGeometry? padding;

  /// Background and border.
  final pw.BoxDecoration? decoration;

  /// Style for the heading text, matching [pw.Header.textStyle].
  final pw.TextStyle? textStyle;

  /// Colour of the document-outline entry.
  final PdfColor? outlineColor;

  /// Style of the document-outline entry.
  final PdfOutlineStyle outlineStyle;

  /// The font to use for Bangla runs.
  final pw.Font? banglaFont;

  /// Style for non-Bangla runs.
  final pw.TextStyle? style;

  /// Style for Bangla runs.
  final pw.TextStyle? banglaStyle;

  /// Creates a [Header].
  Header(
    this.text, {
    this.fontSize = 24,
    this.fontWeight = pw.FontWeight.bold,
    this.child,
    this.level = 0,
    this.title,
    this.margin,
    this.padding,
    this.decoration,
    this.textStyle,
    this.outlineColor,
    this.outlineStyle = PdfOutlineStyle.normal,
    this.banglaFont,
    this.style,
    this.banglaStyle,
  }) : assert(level >= 0 && level <= 5, 'level must be between 0 and 5');

  @override
  pw.Widget build(pw.Context context) {
    return pw.Header(
      level: level,
      title: title ?? text,
      margin: margin,
      padding: padding,
      decoration: decoration,
      outlineColor: outlineColor,
      outlineStyle: outlineStyle,
      child: child ??
          Text(
            text,
            fontSize: fontSize,
            fontWeight: fontWeight,
            banglaFont: banglaFont,
            style: style ?? textStyle,
            banglaStyle: banglaStyle,
          ),
    );
  }
}

/// A paragraph, with Bangla shaped correctly.
///
/// Mirrors [pw.Paragraph], with the text positional. The alignment default is
/// [pw.TextAlign.start] rather than `justify`, which is what this package has
/// always done.
class Paragraph extends pw.StatelessWidget {
  /// The paragraph text.
  final String text;

  /// Font size.
  final double fontSize;

  /// Font weight.
  final pw.FontWeight fontWeight;

  /// Horizontal alignment.
  final pw.TextAlign textAlign;

  /// Space outside the paragraph.
  final pw.EdgeInsetsGeometry margin;

  /// Space inside the paragraph.
  final pw.EdgeInsetsGeometry? padding;

  /// The font to use for Bangla runs.
  final pw.Font? banglaFont;

  /// Style for non-Bangla runs.
  final pw.TextStyle? style;

  /// Style for Bangla runs.
  final pw.TextStyle? banglaStyle;

  /// Creates a [Paragraph].
  Paragraph(
    this.text, {
    this.fontSize = 14,
    this.fontWeight = pw.FontWeight.normal,
    this.textAlign = pw.TextAlign.start,
    this.margin = const pw.EdgeInsets.only(bottom: 12),
    this.padding,
    this.banglaFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    pw.Widget child = Text(
      text,
      fontSize: fontSize,
      fontWeight: fontWeight,
      textAlign: textAlign,
      banglaFont: banglaFont,
      style: style,
      banglaStyle: banglaStyle,
    );
    if (padding != null) {
      child = pw.Padding(padding: padding!, child: child);
    }
    return pw.Container(margin: margin, child: child);
  }
}
