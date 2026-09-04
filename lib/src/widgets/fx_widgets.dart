part of 'package:bangla_pdf/bangla_pdf.dart';

class Text extends pw.StatelessWidget {
  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final PdfColor color;
  final pw.TextAlign? textAlign;
  final pw.TextDirection? textDirection;
  final bool? softWrap;
  final bool tightBounds;
  final double textScaleFactor;
  final int? maxLines;
  final pw.TextOverflow? overflow;
  final pw.Font? banglaFont;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

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
    this.banglaFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    return AutoText(
      text,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      tightBounds: tightBounds,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      overflow: overflow,
      banglaFont: banglaFont,
      style: style,
      banglaStyle: banglaStyle,
    );
  }
}

/// Represents a single text span in a PDF RichText.
class RichTextItem {
  final String text;
  final double fontSize;
  final PdfColor color;
  final pw.Font? banglaFont;

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
              (span) => AutoText(
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

  /// The font to use for Bangla runs in this span.
  final pw.Font? banglaFont;

  /// Creates a [TextSpan].
  TextSpan(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.style,
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
      child: AutoText(
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
    pw.Widget child = AutoText(
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

/// A widget that automatically detects Bangla and non-Bangla text
/// and renders them with the appropriate fonts.
///
/// This widget is the core of the `bangla_pdf` package. It takes a string
/// and splits it into segments of Bangla and non-Bangla text. It then
/// applies the [banglaFont] to Bangla segments and the [generalFont] (or default)
/// to other segments.
class AutoText extends pw.StatelessWidget {
  /// The text to display.
  final String text;

  /// The font size to use. Defaults to 16.
  final double fontSize;

  /// The font weight to use. Defaults to [pw.FontWeight.normal].
  final pw.FontWeight fontWeight;

  /// The color of the text. Defaults to [PdfColors.black].
  final PdfColor color;

  /// How the text should be aligned horizontally.
  final pw.TextAlign? textAlign;

  /// The directionality of the text.
  final pw.TextDirection? textDirection;

  /// Whether the text should break at soft line breaks.
  final bool? softWrap;

  /// Whether the text should be tight to its bounds.
  final bool tightBounds;

  /// The number of font pixels for each logical pixel.
  final double textScaleFactor;

  /// An optional maximum number of lines for the text to span, wrapping if necessary.
  final int? maxLines;

  /// How visual overflow should be handled.
  final pw.TextOverflow? overflow;

  /// The font to use for Bangla text.
  ///
  /// If not provided, the bundled Noto Sans Bengali is used and shaped with
  /// its own OpenType tables. Supply a font from [BanglaPdf.loadFont] to shape
  /// with a different Unicode font; a `pw.Font.ttf` holding a legacy Bijoy
  /// font still takes the 1.0.x ANSI path.
  final pw.Font? banglaFont;

  /// The font to use for non-Bangla text.
  final pw.Font? generalFont;

  /// Additional style to apply to the text.
  final pw.TextStyle? style;

  /// Additional style to apply specifically to Bangla text.
  final pw.TextStyle? banglaStyle;

  /// Creates an [AutoText] widget.
  AutoText(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.textAlign = pw.TextAlign.start,
    this.textDirection,
    this.softWrap,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.maxLines,
    this.overflow,
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
      );
    }

    return pw.RichText(
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      tightBounds: tightBounds,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      overflow: overflow,
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
