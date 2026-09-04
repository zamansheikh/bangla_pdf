/// Drop-in replacements for every `package:pdf` widget that renders text.
///
/// Each class here takes exactly the parameters its `package:pdf` counterpart
/// takes and behaves identically, except that a string containing Bangla is
/// laid out by this package's OpenType shaper instead of `package:pdf`'s
/// glyph-per-codepoint text path.
///
/// A string with no Bengali in it is handed straight to `package:pdf`, so a
/// document with no Bangla in it renders exactly as it would without this
/// package.
library;

// `PdfIndirect` is the declared type of `replaces` on pw's form fields, but
// `package:pdf` never exports it -- forms.dart reaches into the implementation
// for it too. Matching the signature exactly leaves no alternative.
// ignore_for_file: implementation_imports

import 'package:bangla_pdf/src/compat/bridge.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/format/indirect.dart';
import 'package:pdf/widgets.dart' as pw;

// ---------------------------------------------------------------------------
// text.dart
// ---------------------------------------------------------------------------

/// A run of text, with Bangla shaped correctly.
///
/// Mirrors [pw.Text].
class Text extends pw.StatelessWidget {
  /// Creates a [Text].
  Text(
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

  /// Style for the text, merged over the ambient theme.
  final pw.TextStyle? style;

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

  @override
  pw.Widget build(pw.Context context) => BanglaAwareText(
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

/// A span of styled text, with Bangla shaped correctly.
///
/// Extends [pw.TextSpan], so it is a real [pw.InlineSpan] and can be nested
/// with [pw.WidgetSpan] or passed to any `package:pdf` widget that takes one.
class TextSpan extends pw.TextSpan {
  /// Creates a [TextSpan].
  const TextSpan({
    super.style,
    super.text,
    super.baseline,
    super.children,
    super.annotation,
  });
}

/// Rich text with per-span styling, with Bangla shaped correctly.
///
/// Mirrors [pw.RichText]. Spans containing Bangla are shaped and flowed as
/// separate runs; a tree with no Bangla in it is passed to [pw.RichText]
/// untouched, so existing layouts are unaffected.
class RichText extends pw.StatelessWidget {
  /// Creates a [RichText].
  RichText({
    required this.text,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.tightBounds = false,
    this.textScaleFactor = 1.0,
    this.maxLines,
    this.overflow = pw.TextOverflow.visible,
    this.hyphenation,
  });

  /// The span tree to lay out.
  final pw.InlineSpan text;

  /// Horizontal alignment.
  final pw.TextAlign? textAlign;

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
  final pw.TextOverflow overflow;

  /// Word-breaking callback, as in [pw.RichText.hyphenation].
  ///
  /// Honoured on the `package:pdf` path. The shaper breaks on syllable
  /// boundaries, so a shaped line never splits inside a conjunct.
  final pw.Hyphenation? hyphenation;

  pw.Widget _native() => pw.RichText(
        text: text,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        tightBounds: tightBounds,
        textScaleFactor: textScaleFactor,
        maxLines: maxLines,
        overflow: overflow,
        hyphenation: hyphenation,
      );

  @override
  pw.Widget build(pw.Context context) {
    final inherited = pw.Theme.of(context).defaultTextStyle;
    final runs = flattenSpans(text, inherited);
    if (!runs.any((r) => containsBangla(r.text))) return _native();

    // Bangla is present: lay each run out with its own shaper. A single
    // pw.RichText cannot do this, because shaping reorders glyphs across the
    // run and pw measures span-by-span.
    return pw.Wrap(
      crossAxisAlignment: pw.WrapCrossAlignment.end,
      children: <pw.Widget>[
        for (final run in runs)
          BanglaAwareText(
            run.text,
            style: run.style,
            textAlign: textAlign,
            textDirection: textDirection,
            softWrap: softWrap,
            tightBounds: tightBounds,
            textScaleFactor: textScaleFactor,
            overflow: overflow,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// content.dart
// ---------------------------------------------------------------------------

/// A section heading, with Bangla shaped correctly.
///
/// Mirrors [pw.Header], including the PDF outline entry it adds.
class Header extends pw.StatelessWidget {
  /// Creates a [Header].
  Header({
    this.level = 1,
    this.text,
    this.child,
    this.decoration,
    this.margin,
    this.padding,
    this.textStyle,
    String? title,
    this.outlineColor,
    this.outlineStyle = PdfOutlineStyle.normal,
  })  : assert(level >= 0 && level <= 5),
        assert(child != null || text != null),
        title = title ?? text;

  /// The outline entry's title. Defaults to [text].
  final String? title;

  /// The heading text. Ignored when [child] is given.
  final String? text;

  /// A widget to use instead of [text].
  final pw.Widget? child;

  /// Heading level, 0 to 5.
  final int level;

  /// Background and border.
  final pw.BoxDecoration? decoration;

  /// Space outside the heading.
  final pw.EdgeInsetsGeometry? margin;

  /// Space inside the heading.
  final pw.EdgeInsetsGeometry? padding;

  /// Style for the heading text.
  final pw.TextStyle? textStyle;

  /// Colour of the PDF outline entry.
  final PdfColor? outlineColor;

  /// Style of the PDF outline entry.
  final PdfOutlineStyle outlineStyle;

  @override
  pw.Widget build(pw.Context context) {
    final theme = pw.Theme.of(context);
    var effectiveMargin = margin;
    var effectiveStyle = textStyle;

    switch (level) {
      case 0:
        effectiveMargin ??= const pw.EdgeInsets.only(
          bottom: 5.0 * PdfPageFormat.mm,
          top: 10.0 * PdfPageFormat.mm,
        );
        effectiveStyle ??= theme.header0;
      case 1:
        effectiveMargin ??= const pw.EdgeInsets.only(
          bottom: 5.0 * PdfPageFormat.mm,
          top: 10.0 * PdfPageFormat.mm,
        );
        effectiveStyle ??= theme.header1;
      case 2:
        effectiveMargin ??= const pw.EdgeInsets.only(
          bottom: 4.0 * PdfPageFormat.mm,
          top: 8.0 * PdfPageFormat.mm,
        );
        effectiveStyle ??= theme.header2;
      case 3:
        effectiveMargin ??= const pw.EdgeInsets.only(
          bottom: 4.0 * PdfPageFormat.mm,
          top: 6.0 * PdfPageFormat.mm,
        );
        effectiveStyle ??= theme.header3;
      case 4:
        effectiveMargin ??= const pw.EdgeInsets.only(
          top: 2.0 * PdfPageFormat.mm,
          bottom: 4.0 * PdfPageFormat.mm,
        );
        effectiveStyle ??= theme.header4;
      case 5:
        effectiveMargin ??= const pw.EdgeInsets.only(
          top: 2.0 * PdfPageFormat.mm,
          bottom: 4.0 * PdfPageFormat.mm,
        );
        effectiveStyle ??= theme.header5;
    }

    final container = pw.Container(
      alignment: pw.Alignment.topLeft,
      margin: effectiveMargin,
      padding: padding,
      decoration: decoration,
      child: child ?? BanglaAwareText(text!, style: effectiveStyle),
    );

    if (title == null) return container;

    return pw.Outline(
      name: text.hashCode.toString(),
      title: title!,
      level: level,
      color: outlineColor,
      style: outlineStyle,
      child: container,
    );
  }
}

/// A block of body text, with Bangla shaped correctly.
///
/// Mirrors [pw.Paragraph], including its `justify` default.
class Paragraph extends pw.StatelessWidget {
  /// Creates a [Paragraph].
  Paragraph({
    this.text,
    this.textAlign = pw.TextAlign.justify,
    this.style,
    this.margin = const pw.EdgeInsets.only(bottom: 5.0 * PdfPageFormat.mm),
    this.padding,
  });

  /// The paragraph text.
  final String? text;

  /// Horizontal alignment. Defaults to justified, as in [pw.Paragraph].
  final pw.TextAlign textAlign;

  /// Style for the text.
  final pw.TextStyle? style;

  /// Space outside the paragraph.
  final pw.EdgeInsetsGeometry margin;

  /// Space inside the paragraph.
  final pw.EdgeInsetsGeometry? padding;

  @override
  pw.Widget build(pw.Context context) => pw.Container(
        margin: margin,
        padding: padding,
        child: BanglaAwareText(
          text!,
          textAlign: textAlign,
          style: style ?? pw.Theme.of(context).paragraphStyle,
          overflow: pw.TextOverflow.span,
        ),
      );
}

/// One bulleted item, with Bangla shaped correctly.
///
/// Mirrors [pw.Bullet].
class Bullet extends pw.StatelessWidget {
  /// Creates a [Bullet].
  Bullet({
    this.text,
    this.textAlign = pw.TextAlign.left,
    this.style,
    this.margin = const pw.EdgeInsets.only(bottom: 2.0 * PdfPageFormat.mm),
    this.padding,
    this.bulletSize = 2.0 * PdfPageFormat.mm,
    this.bulletMargin = const pw.EdgeInsets.only(
      top: 1.5 * PdfPageFormat.mm,
      left: 5.0 * PdfPageFormat.mm,
      right: 2.0 * PdfPageFormat.mm,
    ),
    this.bulletShape = pw.BoxShape.circle,
    this.bulletColor = PdfColors.black,
  });

  /// The item's text.
  final String? text;

  /// Horizontal alignment.
  final pw.TextAlign textAlign;

  /// Style for the text.
  final pw.TextStyle? style;

  /// Space outside the item.
  final pw.EdgeInsetsGeometry margin;

  /// Space inside the item.
  final pw.EdgeInsetsGeometry? padding;

  /// Space around the bullet marker.
  final pw.EdgeInsetsGeometry bulletMargin;

  /// Diameter of the bullet marker.
  final double bulletSize;

  /// Shape of the bullet marker.
  final pw.BoxShape bulletShape;

  /// Colour of the bullet marker.
  final PdfColor bulletColor;

  @override
  pw.Widget build(pw.Context context) => pw.Container(
        margin: margin,
        padding: padding,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Container(
              width: bulletSize,
              height: bulletSize,
              margin: bulletMargin,
              decoration: pw.BoxDecoration(
                color: bulletColor,
                shape: bulletShape,
              ),
            ),
            pw.Expanded(
              child: text == null
                  ? pw.SizedBox()
                  : BanglaAwareText(
                      text!,
                      textAlign: textAlign,
                      style: pw.Theme.of(context).bulletStyle.merge(style),
                    ),
            ),
          ],
        ),
      );
}

/// A page watermark, with Bangla shaped correctly.
///
/// Mirrors [pw.Watermark].
class Watermark extends pw.StatelessWidget {
  /// Creates a [Watermark] from a widget.
  Watermark({
    required this.child,
    this.fit = pw.BoxFit.contain,
    this.angle = 0,
  });

  /// Creates a [Watermark] from a string.
  Watermark.text(
    String text, {
    pw.TextStyle? style,
    this.fit = pw.BoxFit.contain,
    this.angle = _quarterTurn,
  }) : child = BanglaAwareText(
          text,
          style: style ??
              const pw.TextStyle(
                color: PdfColors.grey200,
                fontWeight: pw.FontWeight.bold,
              ),
        );

  static const double _quarterTurn = 0.7853981633974483; // pi / 4

  /// The watermark content.
  final pw.Widget child;

  /// Rotation in radians.
  final double angle;

  /// How the watermark is scaled into the page.
  final pw.BoxFit fit;

  @override
  pw.Widget build(pw.Context context) => pw.SizedBox.expand(
        child: pw.FittedBox(
          fit: fit,
          child: pw.Transform.rotateBox(angle: angle, child: child),
        ),
      );
}

/// A table of contents built from the document outline, with Bangla shaped
/// correctly.
///
/// Mirrors [pw.TableOfContent]. Outline titles come from [Header], so they are
/// exactly as likely to be Bangla as any other heading.
class TableOfContent extends pw.StatelessWidget {
  /// Creates a [TableOfContent].
  TableOfContent();

  Iterable<pw.Widget> _buildToc(PdfOutline outline, int level) sync* {
    for (final entry in outline.outlines) {
      if (entry.title != null) {
        yield pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Link(
            destination: entry.anchor!,
            child: pw.Row(
              children: <pw.Widget>[
                pw.SizedBox(width: 10.0 * level),
                BanglaAwareText(entry.title!),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Divider(
                    borderStyle: pw.BorderStyle.dotted,
                    thickness: 0.2,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.DelayedWidget(
                  build: (_) => BanglaAwareText('${entry.page}'),
                ),
              ],
            ),
          ),
        );
        yield* _buildToc(entry, level + 1);
      }
    }
  }

  @override
  pw.Widget build(pw.Context context) {
    assert(
      context.page is! pw.MultiPage,
      '$runtimeType will not work with MultiPage',
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[..._buildToc(context.document.outline, 0)],
    );
  }
}

// ---------------------------------------------------------------------------
// table_helper.dart
// ---------------------------------------------------------------------------

/// Builds a [pw.Table] from raw data, with Bangla shaped correctly.
///
/// Mirrors [pw.TableHelper].
mixin TableHelper {
  static pw.TextAlign _textAlign(pw.Alignment align) {
    if (align.x == 0) return pw.TextAlign.center;
    return align.x < 0 ? pw.TextAlign.left : pw.TextAlign.right;
  }

  /// Builds a table from [data], mirroring [pw.TableHelper.fromTextArray].
  static pw.Table fromTextArray({
    pw.Context? context,
    required List<List<dynamic>> data,
    pw.EdgeInsetsGeometry cellPadding = const pw.EdgeInsets.all(5),
    double cellHeight = 0,
    pw.AlignmentGeometry cellAlignment = pw.Alignment.topLeft,
    Map<int, pw.AlignmentGeometry>? cellAlignments,
    pw.TextStyle? cellStyle,
    pw.TextStyle? oddCellStyle,
    pw.OnCellFormat? cellFormat,
    pw.OnCellDecoration? cellDecoration,
    int headerCount = 1,
    List<dynamic>? headers,
    pw.EdgeInsetsGeometry? headerPadding,
    double? headerHeight,
    pw.AlignmentGeometry headerAlignment = pw.Alignment.center,
    Map<int, pw.AlignmentGeometry>? headerAlignments,
    pw.TextStyle? headerStyle,
    pw.OnCellFormat? headerFormat,
    pw.TableBorder? border = const pw.TableBorder(
      left: pw.BorderSide(),
      right: pw.BorderSide(),
      top: pw.BorderSide(),
      bottom: pw.BorderSide(),
      horizontalInside: pw.BorderSide(),
      verticalInside: pw.BorderSide(),
    ),
    Map<int, pw.TableColumnWidth>? columnWidths,
    pw.TableColumnWidth defaultColumnWidth = const pw.IntrinsicColumnWidth(),
    pw.TableWidth tableWidth = pw.TableWidth.max,
    pw.BoxDecoration? headerDecoration,
    pw.BoxDecoration? headerCellDecoration,
    pw.BoxDecoration? rowDecoration,
    pw.BoxDecoration? oddRowDecoration,
    pw.TextDirection? headerDirection,
    pw.TextDirection? tableDirection,
    pw.OnCell? cellBuilder,
    pw.OnCellTextStyle? textStyleBuilder,
  }) {
    assert(headerCount >= 0);

    if (context != null) {
      final theme = pw.Theme.of(context);
      headerStyle ??= theme.tableHeader;
      cellStyle ??= theme.tableCell;
    }

    headerPadding ??= cellPadding;
    headerHeight ??= cellHeight;
    oddRowDecoration ??= rowDecoration;
    oddCellStyle ??= cellStyle;
    cellAlignments ??= const <int, pw.Alignment>{};
    headerAlignments ??= cellAlignments;

    final rows = <pw.TableRow>[];
    var rowNum = 0;

    if (headers != null) {
      final tableRow = <pw.Widget>[];
      for (final dynamic cell in headers) {
        tableRow.add(
          pw.Container(
            alignment: headerAlignments[tableRow.length] ?? headerAlignment,
            padding: headerPadding,
            decoration: headerCellDecoration,
            constraints: pw.BoxConstraints(minHeight: headerHeight),
            child: cell is pw.Widget
                ? cell
                : BanglaAwareText(
                    headerFormat == null
                        ? cell.toString()
                        : headerFormat(tableRow.length, cell),
                    style: headerStyle,
                    textDirection: headerDirection,
                  ),
          ),
        );
      }
      rows.add(
        pw.TableRow(
          repeat: true,
          decoration: headerDecoration,
          children: tableRow,
        ),
      );
      rowNum++;
    }

    final textDirection =
        context == null ? pw.TextDirection.ltr : pw.Directionality.of(context);

    for (final row in data) {
      final tableRow = <pw.Widget>[];
      final isOdd = (rowNum - headerCount) % 2 != 0;

      if (rowNum < headerCount) {
        for (final dynamic cell in row) {
          final align = headerAlignments[tableRow.length] ?? headerAlignment;
          tableRow.add(
            pw.Container(
              alignment: align,
              padding: headerPadding,
              constraints: pw.BoxConstraints(minHeight: headerHeight),
              child: cell is pw.Widget
                  ? cell
                  : BanglaAwareText(
                      headerFormat == null
                          ? cell.toString()
                          : headerFormat(tableRow.length, cell),
                      style: headerStyle,
                      textAlign: _textAlign(align.resolve(textDirection)),
                      textDirection: headerDirection,
                    ),
            ),
          );
        }
      } else {
        for (final dynamic cell in row) {
          final align = cellAlignments[tableRow.length] ?? cellAlignment;
          tableRow.add(
            pw.Container(
              alignment: align,
              padding: cellPadding,
              constraints: pw.BoxConstraints(minHeight: cellHeight),
              decoration: cellDecoration == null
                  ? null
                  : cellDecoration(tableRow.length, cell, rowNum),
              child: cell is pw.Widget
                  ? cell
                  : cellBuilder?.call(tableRow.length, cell, rowNum) ??
                      BanglaAwareText(
                        cellFormat == null
                            ? cell.toString()
                            : cellFormat(tableRow.length, cell),
                        style: textStyleBuilder?.call(
                              tableRow.length,
                              cell,
                              rowNum,
                            ) ??
                            (isOdd ? oddCellStyle : cellStyle),
                        textAlign: _textAlign(align.resolve(textDirection)),
                        textDirection: tableDirection,
                      ),
            ),
          );
        }
      }

      var decoration = isOdd ? oddRowDecoration : rowDecoration;
      if (rowNum < headerCount) decoration = headerDecoration;

      rows.add(
        pw.TableRow(
          repeat: rowNum < headerCount,
          decoration: decoration,
          children: tableRow,
        ),
      );
      rowNum++;
    }

    return pw.Table(
      border: border,
      tableWidth: tableWidth,
      columnWidths: columnWidths,
      defaultColumnWidth: defaultColumnWidth,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      children: rows,
    );
  }
}

// ---------------------------------------------------------------------------
// chart/
// ---------------------------------------------------------------------------

/// A chart legend, with Bangla shaped correctly.
///
/// Mirrors [pw.ChartLegend].
class ChartLegend extends pw.StatelessWidget {
  /// Creates a [ChartLegend].
  ChartLegend({
    this.textStyle,
    this.position = pw.Alignment.topRight,
    this.direction = pw.Axis.vertical,
    this.decoration,
    this.padding = const pw.EdgeInsets.all(5),
  });

  /// Style for the legend labels.
  final pw.TextStyle? textStyle;

  /// Where the legend sits inside the chart.
  final pw.AlignmentGeometry position;

  /// Whether entries stack vertically or run horizontally.
  final pw.Axis direction;

  /// Background and border.
  final pw.BoxDecoration? decoration;

  /// Space inside the legend box.
  final pw.EdgeInsetsGeometry padding;

  pw.Widget _buildLegend(pw.Context context, pw.Dataset dataset) {
    final style = pw.Theme.of(context).defaultTextStyle.merge(textStyle);

    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.Container(
          width: style.fontSize,
          height: style.fontSize,
          margin: const pw.EdgeInsets.only(right: 5),
          child: dataset.legendShape(context),
        ),
        BanglaAwareText(dataset.legend!, style: textStyle),
      ],
    );
  }

  @override
  pw.Widget build(pw.Context context) {
    final datasets = pw.Chart.of(context).datasets;

    final wrap = pw.Wrap(
      direction: direction,
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: direction == pw.Axis.horizontal
          ? pw.WrapCrossAlignment.center
          : pw.WrapCrossAlignment.start,
      children: <pw.Widget>[
        for (final dataset in datasets)
          if (dataset.legend != null) _buildLegend(context, dataset),
      ],
    );

    return pw.Align(
      alignment: position,
      child: pw.Container(
        decoration:
            decoration ?? const pw.BoxDecoration(color: PdfColors.white),
        padding: padding,
        child: wrap,
      ),
    );
  }
}

/// A chart axis with fixed values, whose labels have Bangla shaped correctly.
///
/// Mirrors [pw.FixedAxis]. It supplies a `buildLabel` that shapes Bangla; pass
/// your own to override it, exactly as with [pw.FixedAxis].
class FixedAxis<T extends num> extends pw.FixedAxis<T> {
  /// Creates a [FixedAxis].
  // ignore: use_super_parameters -- `format` is also read by _shapedLabel.
  FixedAxis(
    super.values, {
    pw.GridAxisFormat? format,
    super.textStyle,
    super.margin,
    super.marginStart,
    super.marginEnd,
    super.color,
    super.width,
    super.divisions,
    super.divisionsWidth,
    super.divisionsColor,
    super.divisionsDashed,
    super.ticks,
    super.axisTick,
    super.angle,
    pw.GridAxisBuildLabel? buildLabel,
  }) : super(
          format: format,
          buildLabel: buildLabel ?? _shapedLabel(format, textStyle),
        );

  /// Builds an axis from [values], mirroring [pw.FixedAxis.fromStrings].
  static FixedAxis<int> fromStrings(
    List<String> values, {
    pw.TextStyle? textStyle,
    double? margin,
    double? marginStart,
    double? marginEnd,
    PdfColor? color,
    double? width,
    bool? divisions,
    double? divisionsWidth,
    PdfColor? divisionsColor,
    bool? divisionsDashed,
    bool? ticks,
    bool? axisTick,
    double angle = 0,
    pw.GridAxisBuildLabel? buildLabel,
  }) =>
      FixedAxis<int>(
        List<int>.generate(values.length, (index) => index),
        format: (v) => values[v.toInt()],
        textStyle: textStyle,
        margin: margin,
        marginStart: marginStart,
        marginEnd: marginEnd,
        color: color,
        width: width,
        divisions: divisions,
        divisionsWidth: divisionsWidth,
        divisionsColor: divisionsColor,
        divisionsDashed: divisionsDashed,
        ticks: ticks,
        axisTick: axisTick,
        angle: angle,
        buildLabel: buildLabel,
      );

  /// The label builder used when the caller supplies none.
  ///
  /// Mirrors `package:pdf`'s default of `value.toString()`, then routes the
  /// result through the shaper.
  static pw.GridAxisBuildLabel _shapedLabel(
    pw.GridAxisFormat? format,
    pw.TextStyle? textStyle,
  ) =>
      (value) => BanglaAwareText(
            format == null ? value.toString() : format(value),
            style: textStyle,
          );
}

// ---------------------------------------------------------------------------
// forms.dart
// ---------------------------------------------------------------------------

/// An interactive drop-down field whose value has Bangla shaped correctly.
///
/// Mirrors [pw.ChoiceField]. Only the field's *appearance stream* — what a
/// reader draws before the field is focused — is shaped here. Once a user
/// edits the field, the viewer re-renders it from the form font, which is
/// outside any PDF producer's control.
class ChoiceField extends pw.StatelessWidget with pw.AnnotationAppearance {
  /// Creates a [ChoiceField].
  ChoiceField({
    this.width = 120,
    this.height = 13,
    this.textStyle,
    required this.name,
    required this.items,
    this.value,
    this.replaces,
  });

  /// The form field's name.
  final String name;

  /// Style for the value.
  final pw.TextStyle? textStyle;

  /// Field width.
  final double width;

  /// Field height.
  final double height;

  /// The choices offered.
  final List<String> items;

  /// The initial value.
  final String? value;

  /// An existing annotation to replace.
  final PdfIndirect? replaces;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final style = pw.Theme.of(context).defaultTextStyle.merge(textStyle);
    final pdfRect = context.localToGlobal(box!);

    final field = PdfChoiceField(
      textColor: style.color!,
      fieldName: name,
      value: value,
      font: style.font!.getFont(context),
      fontSize: style.fontSize!,
      items: items,
      rect: pdfRect,
    );

    if (value != null) {
      drawAppearance(
        context,
        field,
        getAppearanceMatrix(context),
        BanglaAwareText(value!, style: style),
        tag: const PdfName('/Tx'),
      );
    }

    PdfAnnot(
      context.page,
      field,
      objser: replaces?.ser,
      objgen: replaces?.gen ?? 0,
    );
  }

  @override
  pw.Widget build(pw.Context context) =>
      pw.SizedBox(width: width, height: height);
}

/// An interactive text field whose value has Bangla shaped correctly.
///
/// Mirrors [pw.TextField]. As with [ChoiceField], only the appearance stream
/// is shaped; a viewer re-renders the field from the form font once edited.
class TextField extends pw.StatelessWidget with pw.AnnotationAppearance {
  /// Creates a [TextField].
  TextField({
    this.child,
    this.width = 120,
    this.height = 13,
    this.textStyle,
    required this.name,
    this.border,
    this.flags,
    this.date,
    this.color,
    this.backgroundColor,
    this.highlighting,
    this.maxLength,
    this.alternateName,
    this.mappingName,
    this.fieldFlags,
    this.value,
    this.defaultValue,
    this.replaces,
  });

  /// A widget drawn behind the field.
  final pw.Widget? child;

  /// Field width.
  final double width;

  /// Field height.
  final double height;

  /// Style for the value.
  final pw.TextStyle? textStyle;

  /// The form field's name.
  final String name;

  /// The field border.
  final PdfBorder? border;

  /// Annotation flags.
  final Set<PdfAnnotFlags>? flags;

  /// Modification date.
  final DateTime? date;

  /// Text colour.
  final PdfColor? color;

  /// Field background.
  final PdfColor? backgroundColor;

  /// Highlighting mode.
  final PdfAnnotHighlighting? highlighting;

  /// Maximum value length.
  final int? maxLength;

  /// Alternate (user-visible) name.
  final String? alternateName;

  /// Mapping name used when exporting.
  final String? mappingName;

  /// Form field flags.
  final Set<PdfFieldFlags>? fieldFlags;

  /// The initial value.
  final String? value;

  /// The value restored by a form reset.
  final String? defaultValue;

  /// An existing annotation to replace.
  final PdfIndirect? replaces;

  @override
  void paint(pw.Context context) {
    super.paint(context);

    final style = pw.Theme.of(context).defaultTextStyle.merge(textStyle);

    final field = PdfTextField(
      rect: context.localToGlobal(box!),
      fieldName: name,
      border: border,
      flags: flags ?? const <PdfAnnotFlags>{PdfAnnotFlags.print},
      date: date,
      color: color,
      backgroundColor: backgroundColor,
      highlighting: highlighting,
      maxLength: maxLength,
      alternateName: alternateName,
      mappingName: mappingName,
      fieldFlags: fieldFlags,
      value: value,
      defaultValue: defaultValue,
      font: style.font!.getFont(context),
      fontSize: style.fontSize!,
      textColor: style.color!,
    );

    if (value != null) {
      drawAppearance(
        context,
        field,
        getAppearanceMatrix(context),
        BanglaAwareText(value!, style: style),
        tag: const PdfName('/Tx'),
      );
    }

    PdfAnnot(
      context.page,
      field,
      objser: replaces?.ser,
      objgen: replaces?.gen ?? 0,
    );
  }

  @override
  pw.Widget build(pw.Context context) =>
      child ?? pw.SizedBox(width: width, height: height);
}
