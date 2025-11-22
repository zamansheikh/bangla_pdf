// ignore_for_file: public_member_api_docs, sort_constructors_first
part of 'package:bangla_pdf/bangla_pdf.dart';

/// Bangla Bullet List
class BulletList extends pw.StatelessWidget {
  final List<String> items;
  final double fontSize;
  final pw.FontWeight fontWeight;
  final pw.Font? banglaFont;
  final pw.PdfColor color;
  final String bullet;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

  BulletList({
    required this.items,
    this.fontSize = 14,
    this.fontWeight = pw.FontWeight.normal,
    this.banglaFont,
    this.color = PdfColors.black,
    this.bullet = "\u2022 ",
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: items.map((item) {
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "$bullet  ",
              style: style ??
                  pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    color: color,
                  ),
            ),
            pw.Expanded(
              child: AutoText(
                item,
                fontSize: fontSize,
                fontWeight: fontWeight,
                banglaFont: banglaFont,
                color: color,
                style: style,
                banglaStyle: banglaStyle,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// A reusable, customizable Bangla table widget for PDF documents.
class Table extends pw.StatelessWidget {
  final List<List<String>> data; // First row treated as header
  final double fontSize;
  final pw.FontWeight fontWeight;
  final pw.Font? banglaFont;
  final pw.PdfColor headerColor;
  final pw.TextAlign headerAlignment;
  final pw.PdfColor borderColor;
  final pw.Alignment cellAlignment;
  final pw.EdgeInsets cellPadding;
  final Map<int, pw.TableColumnWidth>? columnWidths;
  final pw.Font? generalFont;
  final pw.TextStyle? style;
  final pw.TextStyle? banglaStyle;

  Table({
    required this.data,
    this.fontSize = 14,
    this.fontWeight = pw.FontWeight.normal,
    this.banglaFont,
    this.headerColor = PdfColors.grey300,
    this.borderColor = PdfColors.grey,
    this.cellAlignment = pw.Alignment.centerLeft,
    this.cellPadding = const pw.EdgeInsets.all(6),
    this.columnWidths,
    this.headerAlignment = pw.TextAlign.center,
    this.generalFont,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    if (data.isEmpty) return pw.Container();

    // Build header row
    final headerRow = pw.TableRow(
      decoration: pw.BoxDecoration(color: headerColor),
      children: data.first.map((text) {
        return pw.Padding(
          padding: cellPadding,
          child: pw.RichText(
            textAlign: headerAlignment,
            text: pw.TextSpan(
              children: FixingUtils.getAutoLocalizedSpans(
                text: text,
                banglaFont: banglaFont,
                generalFont: generalFont,
                fontSize: fontSize,
                fontWeight: pw.FontWeight.bold,
                style: style?.copyWith(fontWeight: pw.FontWeight.bold),
                banglaStyle:
                    banglaStyle?.copyWith(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        );
      }).toList(),
    );

    // Build body rows
    final bodyRows = data.sublist(1).map((row) {
      return pw.TableRow(
        children: row.map((text) {
          return pw.Padding(
            padding: cellPadding,
            child: pw.Align(
              alignment: cellAlignment,
              child: pw.RichText(
                text: pw.TextSpan(
                  children: FixingUtils.getAutoLocalizedSpans(
                    text: text,
                    banglaFont: banglaFont,
                    generalFont: generalFont,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    style: style,
                    banglaStyle: banglaStyle,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    }).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: [headerRow, ...bodyRows],
    );
  }
}
