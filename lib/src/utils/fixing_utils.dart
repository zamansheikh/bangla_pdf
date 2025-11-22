part of 'package:bangla_pdf/bangla_pdf.dart';

// More Helper Methods will added Here
//
class FixingUtils {
  FixingUtils._();

  //Loading image as Uint8List
  static Future<Uint8List> loadImage(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    return byteData.buffer.asUint8List();
  }

// applying fonts in table data
  static List<List<String>> fixTableData(List<List<String>> tableData) {
    return tableData.map((row) {
      return row.map((cell) {
        // Apply the toFixedUnicode method to each cell if it's a Bangla text
        return cell.fix;
      }).toList();
    }).toList();
  }

  /// Automatically detects Bangla and non-Bangla text and returns a list of TextSpans.
  /// This is useful for rendering mixed text (e.g. Bangla + English) correctly.
  static List<pw.TextSpan> getAutoLocalizedSpans({
    required String text,
    pw.Font? banglaFont,
    pw.Font? generalFont, // For non-Bangla text
    double fontSize = 16,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor color = PdfColors.black,
    pw.TextStyle? style,
    pw.TextStyle? banglaStyle,
  }) {
    final spans = <pw.TextSpan>[];
    // Regex to match Bangla characters, including Danda (।) and Double Danda (॥).
    // Also includes trailing spaces to avoid fragmenting text segments.
    final banglaRegex = RegExp(r'[\u0980-\u09FF\u0964\u0965]+ *');

    // Prepare styles
    final effectiveGeneralStyle = style ??
        pw.TextStyle(
          font: generalFont,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        );

    var effectiveBanglaStyle = banglaStyle ??
        pw.TextStyle(
          font: banglaFont ?? BanglaFontManager().defaultFont,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        );

    // Ensure Bangla font is set if missing in banglaStyle
    if (effectiveBanglaStyle.font == null) {
      effectiveBanglaStyle = effectiveBanglaStyle.copyWith(
        font: banglaFont ?? BanglaFontManager().defaultFont,
      );
    }

    int lastIndex = 0;

    for (final match in banglaRegex.allMatches(text)) {
      // 1. Handle preceding non-Bangla text
      if (match.start > lastIndex) {
        final nonBanglaText = text.substring(lastIndex, match.start);
        spans.add(pw.TextSpan(
          text: nonBanglaText,
          style: effectiveGeneralStyle,
        ));
      }

      // 2. Handle Bangla text
      final banglaText = match.group(0)!.fix;
      spans.add(pw.TextSpan(
        text: banglaText, // Apply the fix extension
        style: effectiveBanglaStyle,
      ));

      lastIndex = match.end;
    }

    // 3. Handle remaining non-Bangla text
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex);
      spans.add(pw.TextSpan(
        text: remainingText,
        style: effectiveGeneralStyle,
      ));
    }

    return spans;
  }
}
