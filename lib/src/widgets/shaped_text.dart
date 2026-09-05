/// The layout and painting widget for shaped Bangla text.
///
/// It shapes the paragraph once, wraps on cluster boundaries so a line can
/// never break inside a conjunct or between a matra and its consonant, and
/// paints each line as real PDF text (`Tj`/`TJ`) addressed by glyph id.
library;

import 'dart:math' as math;

import 'package:bangla_pdf/src/ot/glyph_buffer.dart';
import 'package:bangla_pdf/src/pdf/bangla_font.dart';
import 'package:bangla_pdf/src/pdf/shaped_pdf_font.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One laid-out glyph, positioned relative to the start of its line.
class _PlacedGlyph {
  _PlacedGlyph(
    this.font,
    this.gid,
    this.x,
    this.yOffset,
    this.advance,
    this.text,
  );

  /// The font this glyph id belongs to. With a fallback chain, one line can
  /// draw from several fonts.
  final BanglaUnicodeFont font;

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

/// One shaped cluster, tagged with the font that produced it.
class _Cluster {
  _Cluster(this.font, this.glyphs, this.text, this.width);

  /// The font whose glyph ids [glyphs] refer to.
  final BanglaUnicodeFont font;

  /// The cluster's glyphs, in visual order.
  final List<GlyphInfo> glyphs;

  /// The source text this cluster renders.
  final String text;

  /// Advance width in points, including letter spacing.
  final double width;
}

class _Line {
  _Line(
    this.glyphs,
    this.width,
    this.visualWidth,
    this.text, {
    this.endsParagraph = false,
  });

  final List<_PlacedGlyph> glyphs;

  /// Full advance width including trailing spaces. This is the width the line
  /// occupies, so a widget ending in a space still reserves room for it.
  final double width;

  /// Width up to the last non-space glyph, used only to centre or right-align
  /// so trailing spaces do not shift the visible text.
  final double visualWidth;

  /// The source text of this line, in logical order, for `/ActualText`.
  final String text;

  /// Whether this is the last line of its paragraph. Such a line is left
  /// ragged under [pw.TextAlign.justify], as it is everywhere else.
  final bool endsParagraph;

  /// A copy of this line marked as ending its paragraph.
  _Line lastOfParagraph() =>
      _Line(glyphs, width, visualWidth, text, endsParagraph: true);
}

/// A paragraph of Bangla text rendered through the shaping pipeline.
/// Which lines of a [ShapedTextWidget] belong on the page being laid out.
///
/// `package:pdf` hands one of these back to the widget for each new page, the
/// same way [pw.RichText] tracks the spans it has already drawn.
class ShapedTextContext extends pw.WidgetContext {
  /// Index of the first line to draw on this page.
  int lineStart = 0;

  /// Index just past the last line drawn on this page.
  int lineEnd = 0;

  @override
  void apply(ShapedTextContext other) {
    lineStart = other.lineStart;
    lineEnd = other.lineEnd;
  }

  @override
  pw.WidgetContext clone() => ShapedTextContext()..apply(this);

  @override
  String toString() => 'ShapedTextContext lines $lineStart -> $lineEnd';
}

class ShapedTextWidget extends pw.Widget with pw.SpanningWidget {
  ShapedTextWidget({
    required this.text,
    required this.font,
    required this.fontSize,
    required this.color,
    this.textAlign = pw.TextAlign.start,
    this.lineSpacing = 1.2,
    this.extraLeading = 0,
    this.maxLines,
    this.letterSpacing = 0,
    this.canSpanPages = false,
    this.fallbackFonts = const <BanglaUnicodeFont>[],
    this.softWrap = true,
    this.tightBounds = false,
    this.textDirection = pw.TextDirection.ltr,
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

  /// Extra space added to each line, in points.
  ///
  /// This is what `package:pdf` calls `TextStyle.lineSpacing`; it is kept
  /// separate because [lineSpacing] here is a multiplier, not a length.
  final double extraLeading;

  /// Optional cap on the number of lines rendered.
  final int? maxLines;

  /// Extra space inserted after each cluster, in points.
  final double letterSpacing;

  /// Fonts to try, in order, for runes [font] has no glyph for.
  ///
  /// Mirrors `TextStyle.fontFallback`. Bengali is covered by [font] itself, so
  /// a fallback only ever picks up characters outside it — accented Latin,
  /// currency signs, arrows, emoji — and never splits a Bengali cluster.
  final List<BanglaUnicodeFont> fallbackFonts;

  /// Whether the text wraps at the available width. When false it is laid out
  /// as a single line, as in `package:pdf`.
  final bool softWrap;

  /// Whether the box hugs the glyphs actually drawn rather than the font's
  /// ascent and descent.
  ///
  /// Needs TrueType outlines to measure; a font without a `glyf` table falls
  /// back to the font-wide metrics.
  final bool tightBounds;

  /// Which edge [pw.TextAlign.start] and [pw.TextAlign.end] resolve to.
  ///
  /// Bengali is left-to-right, so this only decides alignment; it does not
  /// reorder text. A right-to-left script mixed into the string is not
  /// reordered either — that needs a bidi pass, which is not implemented.
  final pw.TextDirection textDirection;

  /// Whether the text may be split across pages in a [pw.MultiPage].
  ///
  /// Mirrors `package:pdf`, where a [pw.RichText] spans only when its overflow
  /// is [pw.TextOverflow.span]. Lines are never broken in half; a page ends on
  /// a line boundary.
  final bool canSpanPages;

  List<_Line> _lines = const <_Line>[];
  double _lineHeight = 0;
  double _ascent = 0;
  final ShapedTextContext _context = ShapedTextContext();

  /// Points per design unit for [f], which may not share [font]'s em size.
  double _scaleFor(BanglaUnicodeFont f) => fontSize / f.otf.unitsPerEm;

  /// The first font that can draw [rune], or [font] when none can.
  BanglaUnicodeFont _fontForRune(int rune) {
    if (font.otf.glyphForRune(rune) != null) return font;
    for (final candidate in fallbackFonts) {
      if (candidate.otf.glyphForRune(rune) != null) return candidate;
    }
    return font;
  }

  /// Splits [paragraph] into the longest possible stretches drawable by one
  /// font. A combining mark always stays with the base it follows, so a
  /// fallback boundary can never fall inside a cluster.
  List<(BanglaUnicodeFont, String)> _fontRuns(String paragraph) {
    if (fallbackFonts.isEmpty) {
      return <(BanglaUnicodeFont, String)>[(font, paragraph)];
    }
    final runs = <(BanglaUnicodeFont, String)>[];
    final buffer = StringBuffer();
    BanglaUnicodeFont? current;
    for (final rune in paragraph.runes) {
      final chosen =
          _isCombining(rune) && current != null ? current : _fontForRune(rune);
      if (current != null && chosen != current) {
        runs.add((current, buffer.toString()));
        buffer.clear();
      }
      current = chosen;
      buffer.writeCharCode(rune);
    }
    if (current != null && buffer.isNotEmpty) {
      runs.add((current, buffer.toString()));
    }
    return runs;
  }

  /// Whether [rune] is a combining mark that must not start a new font run.
  static bool _isCombining(int rune) =>
      (rune >= 0x0300 && rune <= 0x036F) || // combining diacriticals
      (rune >= 0x0900 && rune <= 0x0DFF) || // Indic marks live inside these
      (rune >= 0x200C && rune <= 0x200D) || // ZWNJ / ZWJ
      (rune >= 0xFE00 && rune <= 0xFE0F); // variation selectors

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    _ascent = font.ascent * fontSize;
    _lineHeight =
        (font.ascent - font.descent) * fontSize * lineSpacing + extraLeading;

    final limit =
        constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity;

    final lines = <_Line>[];
    for (final paragraph in text.split('\n')) {
      if (paragraph.isEmpty) {
        lines.add(_Line(const <_PlacedGlyph>[], 0, 0, '', endsParagraph: true));
        continue;
      }
      lines.addAll(_layoutParagraph(paragraph, limit));
      if (maxLines != null && lines.length >= maxLines!) break;
    }
    _lines = maxLines == null ? lines : lines.take(maxLines!).toList();

    // How many of the remaining lines fit in the space this page has left.
    // Without spanning the widget claims all of them, exactly as before.
    final start = canSpanPages ? _context.lineStart.clamp(0, _lines.length) : 0;
    var end = _lines.length;
    if (canSpanPages && constraints.hasBoundedHeight && _lineHeight > 0) {
      final fits = (constraints.maxHeight / _lineHeight).floor();
      // At least one line, or a page with too little room would never advance
      // and MultiPage would loop forever.
      end = math.min(_lines.length, start + math.max(1, fits));
    }
    _context
      ..lineStart = start
      ..lineEnd = end;

    final visible = _lines.sublist(start, end);
    final natural = visible.fold<double>(0, (w, l) => math.max(w, l.width));

    var height = _lineHeight * visible.length;
    if (tightBounds && visible.isNotEmpty) {
      // Hug the ink: trim the leading above the tallest glyph and below the
      // deepest one, so the box is what was actually drawn.
      final (inkTop, inkBottom) = _inkExtents(visible);
      if (inkTop != null && inkBottom != null) {
        _ascent = inkTop;
        height = _lineHeight * (visible.length - 1) + (inkTop - inkBottom);
      }
    }

    box = PdfRect(
      0,
      0,
      constraints.constrainWidth(
        constraints.hasBoundedWidth && _resolvedAlign != pw.TextAlign.start
            ? constraints.maxWidth
            : natural,
      ),
      constraints.constrainHeight(height),
    );
  }

  /// Highest and lowest ink across [lines], in points from the baseline.
  ///
  /// Returns nulls when no glyph could be measured — an empty line, or a font
  /// with no TrueType outlines.
  (double?, double?) _inkExtents(List<_Line> lines) {
    double? top;
    double? bottom;
    for (final line in lines) {
      for (final glyph in line.glyphs) {
        final extents = glyph.font.otf.glyphExtents(glyph.gid);
        if (extents == null) continue;
        final scale = _scaleFor(glyph.font);
        final low = extents.$1 * scale + glyph.yOffset;
        final high = extents.$2 * scale + glyph.yOffset;
        top = top == null ? high : math.max(top, high);
        bottom = bottom == null ? low : math.min(bottom, low);
      }
    }
    return (top, bottom);
  }

  /// [textAlign] with `start`/`end` resolved against [textDirection].
  pw.TextAlign get _resolvedAlign => switch (textAlign) {
        pw.TextAlign.start => textDirection == pw.TextDirection.rtl
            ? pw.TextAlign.right
            : textAlign,
        pw.TextAlign.end =>
          textDirection == pw.TextDirection.rtl ? pw.TextAlign.left : textAlign,
        _ => textAlign,
      };

  @override
  bool get canSpan => canSpanPages;

  @override
  bool get hasMoreWidgets => canSpanPages && _context.lineEnd < _lines.length;

  @override
  pw.WidgetContext saveContext() => _context;

  @override
  void restoreContext(ShapedTextContext context) {
    _context.lineStart = context.lineEnd;
  }

  /// Shapes the paragraph once, then wraps it on cluster boundaries.
  List<_Line> _layoutParagraph(String paragraph, double limit) {
    final clusters = _measure(paragraph);
    if (clusters.isEmpty) {
      return <_Line>[
        _Line(const <_PlacedGlyph>[], 0, 0, paragraph, endsParagraph: true),
      ];
    }

    final lines = <_Line>[];
    var start = 0;
    while (start < clusters.length) {
      var end = start;
      var width = 0.0;
      var lastBreak = -1;
      while (end < clusters.length) {
        final next = width + clusters[end].width;
        if (softWrap && limit.isFinite && next > limit && end > start) break;
        width = next;
        if (_isBreakable(clusters[end].text)) lastBreak = end;
        end++;
      }
      // Prefer breaking after the last space rather than mid-word.
      if (end < clusters.length && lastBreak >= start && lastBreak < end - 1) {
        end = lastBreak + 1;
      }
      lines.add(_placeLine(clusters, start, end));
      start = end;
      if (maxLines != null && lines.length >= maxLines!) break;
    }
    if (lines.isNotEmpty) {
      lines[lines.length - 1] = lines.last.lastOfParagraph();
    }
    return lines;
  }

  /// Shapes [paragraph], one stretch per font, and measures every cluster so
  /// wrapping never splits one.
  List<_Cluster> _measure(String paragraph) {
    final out = <_Cluster>[];
    for (final (runFont, chunk) in _fontRuns(paragraph)) {
      if (chunk.isEmpty) continue;
      final run = runFont.shape(chunk);
      if (run.glyphs.isEmpty) continue;
      final scale = _scaleFor(runFont);
      for (final cluster in run.clusters) {
        final glyphs = run.glyphs.sublist(
          cluster.glyphStart,
          cluster.glyphEnd,
        );
        var width = 0.0;
        for (final glyph in glyphs) {
          width += glyph.xAdvance * scale;
        }
        out.add(_Cluster(runFont, glyphs, cluster.text, width + letterSpacing));
      }
    }
    return out;
  }

  _Line _placeLine(List<_Cluster> clusters, int from, int to) {
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
      final scale = _scaleFor(cluster.font);
      // Attach the cluster's text to its first *spacing* glyph. Attached marks
      // are painted in a separate pass, so a mark must never be the carrier or
      // the text would surface out of order during extraction.
      var carrier = 0;
      for (var g = 0; g < cluster.glyphs.length; g++) {
        if (cluster.glyphs[g].xAdvance != 0) {
          carrier = g;
          break;
        }
      }
      for (var g = 0; g < cluster.glyphs.length; g++) {
        final glyph = cluster.glyphs[g];
        placed.add(
          _PlacedGlyph(
            cluster.font,
            glyph.gid,
            pen + glyph.xOffset * scale,
            glyph.yOffset * scale,
            glyph.xAdvance,
            g == carrier ? cluster.text : '',
          ),
        );
        pen += glyph.xAdvance * scale;
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

  static bool _isBreakable(String clusterText) =>
      clusterText.isNotEmpty && clusterText.trim().isEmpty;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final bounds = box;
    if (bounds == null || _lines.isEmpty) return;

    final canvas = context.canvas;
    canvas
      ..saveContext()
      ..setFillColor(color);

    try {
      for (var i = _context.lineStart; i < _context.lineEnd; i++) {
        final line = _lines[i];
        if (line.glyphs.isEmpty) continue;
        final baseline = bounds.bottom +
            bounds.height -
            _ascent -
            (i - _context.lineStart) * _lineHeight;
        final originX =
            bounds.left + _alignOffset(bounds.width, line.visualWidth);
        _paintLine(
          context,
          line,
          originX,
          baseline,
          _justifyShifts(line, bounds.width),
        );
      }
    } finally {
      canvas.restoreContext();
    }
  }

  /// Extra x for each glyph so the line fills [available], for
  /// [pw.TextAlign.justify]. Returns `null` when the line is left as it is.
  ///
  /// The slack is shared equally between word gaps, and every glyph after a
  /// gap moves by the running total. Marks carry absolute positions, so they
  /// shift with the glyph they sit over.
  List<double>? _justifyShifts(_Line line, double available) {
    if (_resolvedAlign != pw.TextAlign.justify || line.endsParagraph) {
      return null;
    }
    final slack = available - line.visualWidth;
    if (slack <= 0 || line.glyphs.isEmpty) return null;

    var lastVisible = -1;
    for (var i = line.glyphs.length - 1; i >= 0; i--) {
      if (line.glyphs[i].text != ' ') {
        lastVisible = i;
        break;
      }
    }
    final gaps = <int>[
      for (var i = 0; i < lastVisible; i++)
        if (line.glyphs[i].text == ' ') i,
    ];
    if (gaps.isEmpty) return null;

    final per = slack / gaps.length;
    final shifts = List<double>.filled(line.glyphs.length, 0);
    var running = 0.0;
    var next = 0;
    for (var i = 0; i < line.glyphs.length; i++) {
      shifts[i] = running;
      if (next < gaps.length && i == gaps[next]) {
        running += per;
        next++;
      }
    }
    return shifts;
  }

  double _alignOffset(double available, double lineWidth) =>
      switch (_resolvedAlign) {
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
    pw.Context context,
    _Line line,
    double originX,
    double baseline,
    List<double>? shifts,
  ) {
    final canvas = context.canvas;
    final flow = <_PlacedGlyph>[];
    final flowShift = <double>[];
    final marks = <_PlacedGlyph>[];
    final markShift = <double>[];
    for (var i = 0; i < line.glyphs.length; i++) {
      final glyph = line.glyphs[i];
      final shift = shifts == null ? 0.0 : shifts[i];
      if (glyph.advance == 0 && (glyph.x != 0 || glyph.yOffset != 0)) {
        marks.add(glyph);
        markShift.add(shift);
      } else {
        flow.add(glyph);
        flowShift.add(shift);
      }
    }

    // One PDF font handle per font that appears on this line.
    final handles = <BanglaUnicodeFont, ShapedPdfFont>{};
    ShapedPdfFont handleFor(BanglaUnicodeFont f) =>
        handles[f] ??= f.pdfFontFor(context.document);

    // Wrap the whole line in an /ActualText span carrying its logical text.
    // Any font can carry it: the span holds text, not glyphs.
    final spanned = line.text.isNotEmpty;
    final spanFont = handleFor(font);
    if (spanned) {
      canvas.drawString(
        spanFont,
        fontSize,
        ShapedPdfFont.beginSpan(line.text),
        0,
        0,
      );
    }

    // Consecutive glyphs sharing a font go out as one show, so a fallback
    // costs an extra operator only where the font actually changes.
    var i = 0;
    while (i < flow.length) {
      final runFont = flow[i].font;
      final pdfFont = handleFor(runFont);
      final scale = _scaleFor(runFont);
      final cids = <int>[];
      final adjustments = <int>[];
      final startX = originX + flow[i].x + flowShift[i];
      var pen = startX;
      while (i < flow.length && flow[i].font == runFont) {
        final glyph = flow[i];
        final want = originX + glyph.x + flowShift[i];
        // TJ numbers move the pen left, in thousandths of the font size.
        adjustments.add(((pen - want) * 1000 / fontSize).round());
        cids.add(pdfFont.cidFor(glyph.gid, glyph.text, glyph.advance));
        pen = want + glyph.advance * scale;
        i++;
      }
      canvas.drawString(
        pdfFont,
        fontSize,
        ShapedPdfFont.encode(cids, adjustments),
        startX,
        baseline,
      );
    }

    for (var m = 0; m < marks.length; m++) {
      final mark = marks[m];
      final pdfFont = handleFor(mark.font);
      canvas.drawString(
        pdfFont,
        fontSize,
        ShapedPdfFont.encode(
          <int>[pdfFont.cidFor(mark.gid, mark.text, mark.advance)],
          <int>[0],
        ),
        originX + mark.x + markShift[m],
        baseline + mark.yOffset,
      );
    }

    if (spanned) {
      canvas.drawString(spanFont, fontSize, ShapedPdfFont.endSpan(), 0, 0);
    }
  }
}
