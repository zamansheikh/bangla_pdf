/// The layout and painting widget for shaped Bangla text.
///
/// It shapes the paragraph once, wraps on cluster boundaries so a line can
/// never break inside a conjunct or between a matra and its consonant, and
/// paints each line as real PDF text (`Tj`/`TJ`) addressed by glyph id.
library;

import 'dart:math' as math;

import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/src/pdf/shaped_pdf_font.dart';
import 'package:bangla_pdf/src/shaping/bengali_shaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One laid-out glyph, positioned relative to the start of its line.
class _PlacedGlyph {
  _PlacedGlyph(this.gid, this.x, this.yOffset, this.advance, this.text);

  final int gid;

  /// Advance in font units, after GPOS. Written into the font's `/W` array so
  /// the content stream needs no correcting kerns.
  final int advance;

  /// Pen position for this glyph, in points from the line start.
  final double x;

  /// Vertical offset from the baseline, in points.
  final double yOffset;

  /// The source text this glyph is responsible for in `/ToUnicode`.
  ///
  /// The first glyph of a cluster carries the cluster's whole text; the rest
  /// carry none, so extraction yields logical order even though the glyphs are
  /// in visual order.
  final String text;
}

class _Line {
  _Line(this.glyphs, this.width, this.visualWidth, this.text);

  final List<_PlacedGlyph> glyphs;

  /// Full advance width including trailing spaces. This is the width the line
  /// occupies, so a widget ending in a space still reserves room for it.
  final double width;

  /// Width up to the last non-space glyph, used only to centre or right-align
  /// so trailing spaces do not shift the visible text.
  final double visualWidth;

  /// The source text of this line, in logical order, for `/ActualText`.
  final String text;
}

/// A paragraph of Bangla text rendered through the shaping pipeline.
class ShapedTextWidget extends pw.Widget {
  ShapedTextWidget({
    required this.text,
    required this.font,
    required this.fontSize,
    required this.color,
    this.textAlign = pw.TextAlign.start,
    this.lineSpacing = 1.2,
    this.maxLines,
    this.letterSpacing = 0,
  });

  /// The source text, in logical order.
  final String text;

  /// The font used to shape and draw.
  final BanglaUnicodeFont font;

  /// Font size in points.
  final double fontSize;

  /// Fill colour.
  final PdfColor color;

  /// Horizontal alignment within the available width.
  final pw.TextAlign textAlign;

  /// Line height as a multiple of the font's natural line height.
  final double lineSpacing;

  /// Optional cap on the number of lines rendered.
  final int? maxLines;

  /// Extra space inserted after each cluster, in points.
  final double letterSpacing;

  List<_Line> _lines = const <_Line>[];
  double _lineHeight = 0;
  double _ascent = 0;

  double get _scale => fontSize / font.otf.unitsPerEm;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    _ascent = font.ascent * fontSize;
    _lineHeight = (font.ascent - font.descent) * fontSize * lineSpacing;

    final limit =
        constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity;

    final lines = <_Line>[];
    for (final paragraph in text.split('\n')) {
      if (paragraph.isEmpty) {
        lines.add(_Line(const <_PlacedGlyph>[], 0, 0, ''));
        continue;
      }
      lines.addAll(_layoutParagraph(paragraph, limit));
      if (maxLines != null && lines.length >= maxLines!) break;
    }
    _lines = maxLines == null ? lines : lines.take(maxLines!).toList();

    final natural = _lines.fold<double>(0, (w, l) => math.max(w, l.width));
    box = PdfRect(
      0,
      0,
      constraints.constrainWidth(
        constraints.hasBoundedWidth && textAlign != pw.TextAlign.start
            ? constraints.maxWidth
            : natural,
      ),
      constraints.constrainHeight(_lineHeight * _lines.length),
    );
  }

  /// Shapes the paragraph once, then wraps it on cluster boundaries.
  List<_Line> _layoutParagraph(String paragraph, double limit) {
    final run = font.shape(paragraph);
    if (run.glyphs.isEmpty) {
      return <_Line>[_Line(const <_PlacedGlyph>[], 0, 0, paragraph)];
    }

    // Measure every cluster so wrapping never splits one.
    final clusters = run.clusters;
    final widths = List<double>.filled(clusters.length, 0);
    for (var c = 0; c < clusters.length; c++) {
      var sum = 0.0;
      for (var g = clusters[c].glyphStart; g < clusters[c].glyphEnd; g++) {
        sum += run.glyphs[g].xAdvance * _scale;
      }
      widths[c] = sum + letterSpacing;
    }

    final lines = <_Line>[];
    var start = 0;
    while (start < clusters.length) {
      var end = start;
      var width = 0.0;
      var lastBreak = -1;
      while (end < clusters.length) {
        final next = width + widths[end];
        if (limit.isFinite && next > limit && end > start) break;
        width = next;
        if (_isBreakable(clusters[end].text)) lastBreak = end;
        end++;
      }
      // Prefer breaking after the last space rather than mid-word.
      if (end < clusters.length && lastBreak >= start && lastBreak < end - 1) {
        end = lastBreak + 1;
      }
      lines.add(_placeLine(run, clusters, widths, start, end));
      start = end;
      if (maxLines != null && lines.length >= maxLines!) break;
    }
    return lines;
  }

  static bool _isBreakable(String clusterText) =>
      clusterText.isNotEmpty && clusterText.trim().isEmpty;

  _Line _placeLine(
    ShapedRun run,
    List<ShapedCluster> clusters,
    List<double> widths,
    int from,
    int to,
  ) {
    final placed = <_PlacedGlyph>[];
    var pen = 0.0;
    // Trailing whitespace must not count towards the line width, or centred
    // and right-aligned text drifts.
    var visualEnd = to;
    while (visualEnd > from && _isBreakable(clusters[visualEnd - 1].text)) {
      visualEnd--;
    }
    var visualWidth = 0.0;

    for (var c = from; c < to; c++) {
      final cluster = clusters[c];
      // Attach the cluster's text to its first *spacing* glyph. Attached marks
      // are painted in a separate pass, so a mark must never be the carrier or
      // the text would surface out of order during extraction.
      var carrier = cluster.glyphStart;
      for (var g = cluster.glyphStart; g < cluster.glyphEnd; g++) {
        if (run.glyphs[g].xAdvance != 0) {
          carrier = g;
          break;
        }
      }
      for (var g = cluster.glyphStart; g < cluster.glyphEnd; g++) {
        final glyph = run.glyphs[g];
        placed.add(
          _PlacedGlyph(
            glyph.gid,
            pen + glyph.xOffset * _scale,
            glyph.yOffset * _scale,
            glyph.xAdvance,
            g == carrier ? cluster.text : '',
          ),
        );
        pen += glyph.xAdvance * _scale;
      }
      pen += letterSpacing;
      if (c < visualEnd) visualWidth = pen;
    }
    final source = StringBuffer();
    for (var c = from; c < to; c++) {
      source.write(clusters[c].text);
    }
    return _Line(placed, pen, visualWidth, source.toString());
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final bounds = box;
    if (bounds == null || _lines.isEmpty) return;

    final pdfFont = font.pdfFontFor(context.document);
    final canvas = context.canvas;
    canvas
      ..saveContext()
      ..setFillColor(color);

    try {
      for (var i = 0; i < _lines.length; i++) {
        final line = _lines[i];
        if (line.glyphs.isEmpty) continue;
        final baseline =
            bounds.bottom + bounds.height - _ascent - i * _lineHeight;
        final originX =
            bounds.left + _alignOffset(bounds.width, line.visualWidth);
        _paintLine(canvas, pdfFont, line, originX, baseline);
      }
    } finally {
      canvas.restoreContext();
    }
  }

  double _alignOffset(double available, double lineWidth) =>
      switch (textAlign) {
        pw.TextAlign.center => (available - lineWidth) / 2,
        pw.TextAlign.right || pw.TextAlign.end => available - lineWidth,
        _ => 0,
      };

  /// Emits one line as PDF text.
  ///
  /// Spacing glyphs go into a single `TJ` array with no kerning corrections,
  /// so a text extractor sees one uninterrupted run and does not invent word
  /// breaks. Zero-width attached marks are painted afterwards at absolute
  /// positions; they carry no `/ToUnicode` text, so they add nothing to the
  /// extracted string.
  void _paintLine(
    PdfGraphics canvas,
    ShapedPdfFont pdfFont,
    _Line line,
    double originX,
    double baseline,
  ) {
    final flow = <_PlacedGlyph>[];
    final marks = <_PlacedGlyph>[];
    for (final glyph in line.glyphs) {
      if (glyph.advance == 0 && (glyph.x != 0 || glyph.yOffset != 0)) {
        marks.add(glyph);
      } else {
        flow.add(glyph);
      }
    }

    // Wrap the whole line in an /ActualText span carrying its logical text.
    final spanned = line.text.isNotEmpty;
    if (spanned) {
      canvas.drawString(
        pdfFont,
        fontSize,
        ShapedPdfFont.beginSpan(line.text),
        0,
        0,
      );
    }

    if (flow.isNotEmpty) {
      final cids = <int>[];
      final adjustments = <int>[];
      final startX = originX + flow.first.x;
      var pen = startX;
      for (final glyph in flow) {
        final want = originX + glyph.x;
        // TJ numbers move the pen left, in thousandths of the font size.
        final adjust = ((pen - want) * 1000 / fontSize).round();
        cids.add(pdfFont.cidFor(glyph.gid, glyph.text, glyph.advance));
        adjustments.add(adjust);
        pen = want + glyph.advance * _scale;
      }
      canvas.drawString(
        pdfFont,
        fontSize,
        ShapedPdfFont.encode(cids, adjustments),
        startX,
        baseline,
      );
    }

    for (final mark in marks) {
      canvas.drawString(
        pdfFont,
        fontSize,
        ShapedPdfFont.encode(
          <int>[pdfFont.cidFor(mark.gid, mark.text, mark.advance)],
          <int>[0],
        ),
        originX + mark.x,
        baseline + mark.yOffset,
      );
    }

    if (spanned) {
      canvas.drawString(pdfFont, fontSize, ShapedPdfFont.endSpan(), 0, 0);
    }
  }
}
