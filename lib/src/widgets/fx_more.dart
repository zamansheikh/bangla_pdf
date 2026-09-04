// ignore_for_file: public_member_api_docs, sort_constructors_first
part of 'package:bangla_pdf/bangla_pdf.dart';

/// A bulleted list, with Bangla shaped correctly.
///
/// [pw.Bullet] renders a single item; this renders a whole list, and takes the
/// same styling parameters so it reads the same way.
class BulletList extends pw.StatelessWidget {
  /// The items, one per line.
  final List<String> items;

  /// Font size.
  final double fontSize;

  /// Font weight.
  final pw.FontWeight fontWeight;

  /// The font to use for Bangla runs.
  final pw.Font? banglaFont;

  /// Text colour.
  final pw.PdfColor color;

  /// The marker drawn before each item.
  ///
  /// Replaced automatically when the resolved font has no glyph for it.
  final String bullet;

  /// Colour of the marker; defaults to [color].
  final pw.PdfColor? bulletColor;

  /// Space outside the list.
  final pw.EdgeInsetsGeometry? margin;

  /// Space inside the list.
  final pw.EdgeInsetsGeometry? padding;

  /// Space between one item and the next.
  final double itemSpacing;

  /// Horizontal alignment of each item.
  final pw.TextAlign textAlign;

  /// Style for non-Bangla runs.
  final pw.TextStyle? style;

  /// Style for Bangla runs.
  final pw.TextStyle? banglaStyle;

  /// Creates a [BulletList].
  BulletList({
    required this.items,
    this.fontSize = 14,
    this.fontWeight = pw.FontWeight.normal,
    this.banglaFont,
    this.color = PdfColors.black,
    this.bullet = "\u2022 ",
    this.bulletColor,
    this.margin,
    this.padding,
    this.itemSpacing = 0,
    this.textAlign = pw.TextAlign.start,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    // Not every Bangla font carries U+2022; Kalpurush does not. Fall back to
    // a marker the font can actually draw rather than emitting a blank.
    var marker = bullet;
    if (!BanglaPdf.covers(banglaFont ?? banglaStyle?.font, marker)) {
      for (final candidate in const <String>['\u2022 ', '\u00B7 ', '- ']) {
        if (BanglaPdf.covers(banglaFont ?? banglaStyle?.font, candidate)) {
          marker = candidate;
          break;
        }
      }
    }

    pw.Widget list = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: items.map((item) {
        return pw.Padding(
          padding: pw.EdgeInsets.only(bottom: itemSpacing),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Route the marker through AutoText too, so it is drawn with a
              // real font instead of falling back to base-14 Helvetica, which
              // has no glyph for the default bullet.
              AutoText(
                "$marker  ",
                fontSize: fontSize,
                fontWeight: fontWeight,
                banglaFont: banglaFont,
                color: bulletColor ?? color,
                style: style,
                banglaStyle: banglaStyle,
              ),
              pw.Expanded(
                child: AutoText(
                  item,
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  textAlign: textAlign,
                  banglaFont: banglaFont,
                  color: color,
                  style: style,
                  banglaStyle: banglaStyle,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
    if (padding != null) {
      list = pw.Padding(padding: padding!, child: list);
    }
    if (margin != null) {
      list = pw.Container(margin: margin, child: list);
    }
    return list;
  }
}

/// A table, with Bangla shaped correctly in every cell.
///
/// Modelled on [pw.TableHelper.fromTextArray] so the styling parameters read
/// the same way. The first row of [data] is the header unless [headerCount] is
/// changed.
class Table extends pw.StatelessWidget {
  /// Row data. The first [headerCount] rows are headers.
  final List<List<String>> data;

  /// How many leading rows are headers. 0 for none.
  final int headerCount;

  /// Font size for every cell.
  final double fontSize;

  /// Font weight for body cells.
  final pw.FontWeight fontWeight;

  /// The font to use for Bangla runs.
  final pw.Font? banglaFont;

  /// The font to use for non-Bangla runs.
  final pw.Font? generalFont;

  /// Background of the header row.
  final pw.PdfColor headerColor;

  /// Text colour in header cells.
  final pw.PdfColor? headerTextColor;

  /// Horizontal alignment of header text.
  final pw.TextAlign headerAlignment;

  /// Style for header cells; overrides [headerColor] and [fontSize].
  final pw.TextStyle? headerStyle;

  /// Padding inside header cells; defaults to [cellPadding].
  final pw.EdgeInsetsGeometry? headerPadding;

  /// Fixed header row height, or 0 to size to content.
  final double? headerHeight;

  /// Decoration behind the whole header row.
  final pw.BoxDecoration? headerDecoration;

  /// Style for body cells.
  final pw.TextStyle? cellStyle;

  /// Text colour in body cells.
  final pw.PdfColor cellTextColor;

  /// Padding inside body cells.
  final pw.EdgeInsetsGeometry cellPadding;

  /// Fixed body row height, or 0 to size to content.
  final double cellHeight;

  /// Alignment of body cell contents.
  final pw.AlignmentGeometry cellAlignment;

  /// Per-column alignment overrides.
  final Map<int, pw.AlignmentGeometry>? cellAlignments;

  /// Decoration behind every body row.
  final pw.BoxDecoration? rowDecoration;

  /// Decoration behind odd body rows, for banding.
  final pw.BoxDecoration? oddRowDecoration;

  /// Colour of the default border.
  final pw.PdfColor borderColor;

  /// Border, or null for none. Overrides [borderColor].
  final pw.TableBorder? border;

  /// Fixed column widths, by index.
  final Map<int, pw.TableColumnWidth>? columnWidths;

  /// Width strategy for columns with no explicit width.
  final pw.TableColumnWidth defaultColumnWidth;

  /// How the table sizes itself horizontally.
  final pw.TableWidth tableWidth;

  /// Vertical alignment inside cells.
  final pw.TableCellVerticalAlignment defaultVerticalAlignment;

  /// Style for non-Bangla runs.
  final pw.TextStyle? style;

  /// Style for Bangla runs.
  final pw.TextStyle? banglaStyle;

  /// Creates a [Table].
  Table({
    required this.data,
    this.headerCount = 1,
    this.fontSize = 14,
    this.fontWeight = pw.FontWeight.normal,
    this.banglaFont,
    this.generalFont,
    this.headerColor = PdfColors.grey300,
    this.headerTextColor,
    this.headerAlignment = pw.TextAlign.center,
    this.headerStyle,
    this.headerPadding,
    this.headerHeight,
    this.headerDecoration,
    this.cellStyle,
    this.cellTextColor = PdfColors.black,
    this.cellPadding = const pw.EdgeInsets.all(6),
    this.cellHeight = 0,
    this.cellAlignment = pw.Alignment.centerLeft,
    this.cellAlignments,
    this.rowDecoration,
    this.oddRowDecoration,
    this.borderColor = PdfColors.grey,
    this.border,
    this.columnWidths,
    this.defaultColumnWidth = const pw.IntrinsicColumnWidth(),
    this.tableWidth = pw.TableWidth.max,
    this.defaultVerticalAlignment = pw.TableCellVerticalAlignment.middle,
    this.style,
    this.banglaStyle,
  });

  @override
  pw.Widget build(pw.Context context) {
    if (data.isEmpty) return pw.Container();
    final headers = data.take(headerCount).toList();
    final body = data.skip(headerCount).toList();

    pw.Widget cell(
      String text, {
      required bool header,
      required int column,
    }) {
      final resolved = header
          ? (headerStyle ?? style?.copyWith(fontWeight: pw.FontWeight.bold))
          : (cellStyle ?? style);
      final content = AutoText(
        text,
        textAlign: header ? headerAlignment : pw.TextAlign.start,
        fontSize: fontSize,
        fontWeight: header ? pw.FontWeight.bold : fontWeight,
        color: header ? (headerTextColor ?? cellTextColor) : cellTextColor,
        banglaFont: banglaFont,
        generalFont: generalFont,
        style: resolved,
        banglaStyle: header
            ? banglaStyle?.copyWith(fontWeight: pw.FontWeight.bold)
            : banglaStyle,
      );
      final padded = pw.Padding(
        padding: (header ? headerPadding : null) ?? cellPadding,
        child: content,
      );
      if (header) return padded;
      return pw.Align(
        alignment: cellAlignments?[column] ?? cellAlignment,
        child: padded,
      );
    }

    final rows = <pw.TableRow>[
      for (final row in headers)
        pw.TableRow(
          repeat: true,
          decoration: headerDecoration ?? pw.BoxDecoration(color: headerColor),
          children: <pw.Widget>[
            for (var c = 0; c < row.length; c++)
              pw.SizedBox(
                height: headerHeight == null || headerHeight == 0
                    ? null
                    : headerHeight,
                child: cell(row[c], header: true, column: c),
              ),
          ],
        ),
      for (var r = 0; r < body.length; r++)
        pw.TableRow(
          decoration: (r.isOdd ? oddRowDecoration : null) ?? rowDecoration,
          children: <pw.Widget>[
            for (var c = 0; c < body[r].length; c++)
              pw.SizedBox(
                height: cellHeight == 0 ? null : cellHeight,
                child: cell(body[r][c], header: false, column: c),
              ),
          ],
        ),
    ];

    return pw.Table(
      border: border ?? pw.TableBorder.all(color: borderColor),
      defaultVerticalAlignment: defaultVerticalAlignment,
      columnWidths: columnWidths,
      defaultColumnWidth: defaultColumnWidth,
      tableWidth: tableWidth,
      children: rows,
    );
  }
}
