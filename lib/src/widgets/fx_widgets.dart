part of 'package:bangla_pdf/bangla_pdf.dart';

class Text extends pw.StatelessWidget {
  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final PdfColor color;
  final pw.TextAlign textAlign;
  final pw.Font? banglaFont;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

  Text(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.textAlign = pw.TextAlign.start,
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

/// A reusable RichText widget for PDF documents supporting automatic Bangla detection.
class RichText extends pw.StatelessWidget {
  final List<TextSpan> spans;
  final pw.TextAlign textAlign;

  RichText({
    required this.spans,
    this.textAlign = pw.TextAlign.start,
  });

  @override
  pw.Widget build(pw.Context context) {
    final List<pw.InlineSpan> children = [];

    for (final span in spans) {
      children.addAll(FixingUtils.getAutoLocalizedSpans(
        text: span.text,
        banglaFont: span.banglaFont,
        fontSize: span.fontSize,
        fontWeight: span.fontWeight,
        color: span.color,
      ));
    }

    return pw.RichText(
      textAlign: textAlign,
      text: pw.TextSpan(children: children),
    );
  }
}

/// A text span for BanglaRichText
class TextSpan {
  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final PdfColor color;
  final pw.Font? banglaFont;

  TextSpan(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.banglaFont,
  });
}

/// Header widget (like pw.Header but with Bangla support)
class Header extends pw.StatelessWidget {
  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final pw.Font? banglaFont;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

  Header(
    this.text, {
    this.fontSize = 24,
    this.fontWeight = pw.FontWeight.bold,
    this.banglaFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Header(
      level: 0,
      child: AutoText(
        text,
        fontSize: fontSize,
        fontWeight: fontWeight,
        banglaFont: banglaFont,
        style: style,
        banglaStyle: banglaStyle,
      ),
    );
  }
}

/// Paragraph widget (like pw.Paragraph but Bangla)
class Paragraph extends pw.StatelessWidget {
  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final pw.TextAlign textAlign;
  final pw.Font? banglaFont;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

  Paragraph(
    this.text, {
    this.fontSize = 14,
    this.fontWeight = pw.FontWeight.normal,
    this.textAlign = pw.TextAlign.start,
    this.banglaFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: AutoText(
        text,
        fontSize: fontSize,
        fontWeight: fontWeight,
        textAlign: textAlign,
        banglaFont: banglaFont,
        style: style,
        banglaStyle: banglaStyle,
      ),
    );
  }
}

/// A widget that automatically detects Bangla and non-Bangla text
/// and renders them with the appropriate fonts.
class AutoText extends pw.StatelessWidget {
  final String text;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final PdfColor color;
  final pw.TextAlign textAlign;
  final pw.Font? banglaFont;
  final pw.Font? generalFont;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

  AutoText(
    this.text, {
    this.fontSize = 16,
    this.fontWeight = pw.FontWeight.normal,
    this.color = PdfColors.black,
    this.textAlign = pw.TextAlign.start,
    this.banglaFont,
    this.generalFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.RichText(
      textAlign: textAlign,
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
