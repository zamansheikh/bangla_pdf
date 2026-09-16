/// Walks a page's content stream and produces text runs.
///
/// Only the text operators matter here. Everything else is skipped, including
/// paths and images — except that an image with no accompanying text is what
/// tells us a page is a scan.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/extract/font_info.dart';
import 'package:bangla_pdf/src/extract/pdf_lexer.dart';
import 'package:bangla_pdf/src/extract/pdf_object.dart';

/// Stands for a large negative `TJ` adjustment inside a collected glyph run:
/// the way most producers write a space without drawing one. Glyph ids are
/// never negative, so it cannot be mistaken for a glyph.
const int kWordGap = -1;

/// Operators that end a run of glyphs being collected for reading back.
///
/// Text objects and positioning are deliberately absent. Word places every
/// glyph with its own `Tm`, and on a justified line gives every glyph its own
/// `BT` … `ET` as well, so neither says where a word ends. Geometry does: a run
/// carries on while each glyph starts where the last one finished, gains a word
/// gap when there is empty space between them, and ends when the line changes.
///
/// Marked content is absent too, for the same reason: a tagged PDF wraps every
/// text object in a structure tag (`/P <</MCID 13>> BDC … EMC`). Only a span
/// that carries `/ActualText` changes what its glyphs mean, and that is handled
/// where the span opens and closes.
///
/// So is the graphics state. Word clips each glyph of a table cell to the cell
/// with `q … re W* n … Q`, mid-word, and a transformation is taken into account
/// by comparing positions in device space.
const Set<String> _runBreakingOperators = <String>{"'", '"', 'Do', 'BI'};

/// One run of text drawn with a single font.
class TextRun {
  TextRun({
    required this.text,
    required this.font,
    required this.x,
    required this.y,
    required this.fontSize,
  });

  /// The text as recovered from the font's own mapping, before any Bijoy
  /// conversion.
  final String text;

  /// The font it was drawn with, or `null` when the resource was missing.
  final FontInfo? font;

  /// Position in unscaled text space; enough to order runs on the page.
  final double x;
  final double y;

  /// Size in text space units.
  final double fontSize;

  /// Which text object (`BT` … `ET`) this run came from.
  ///
  /// Producers that lay out word by word — which is what the 1.0.x Bijoy path
  /// does — emit one text object per word and no space glyph between them.
  /// A change of text object on the same line therefore implies a space.
  int objectIndex = 0;

  @override
  String toString() => '[$x,$y] $text';
}

/// What a page walk found.
class PageContent {
  PageContent({
    required this.runs,
    required this.imageCount,
    required this.actualTextUsed,
  });

  /// Text runs in content-stream order.
  final List<TextRun> runs;

  /// How many images the page draws. A page with images and no text is a scan.
  final int imageCount;

  /// Whether any `/ActualText` span was honoured, which means the producer
  /// told us the logical text directly.
  final bool actualTextUsed;
}

/// Extracts the text runs of one page.
///
/// [fonts] maps a resource name to its parsed font.
PageContent walkContentStream(Uint8List content, Map<String, FontInfo> fonts) {
  final lexer = PdfLexer(content);
  final operands = <PdfObj>[];
  final runs = <TextRun>[];
  var imageCount = 0;
  var actualTextUsed = false;

  FontInfo? currentFont;
  var fontSize = 0.0;
  // Text-space translation.
  var tx = 0.0;
  var ty = 0.0;

  // The current transformation matrix, as [a, b, c, d, e, f]. Widgets are
  // usually each wrapped in their own `cm`, so text-space coordinates repeat
  // from widget to widget and only the CTM separates one line from the next.
  var ctm = <double>[1, 0, 0, 1, 0, 0];
  final ctmStack = <List<double>>[];
  var objectIndex = 0;
  var lineX = 0.0;
  var lineY = 0.0;
  var leading = 0.0;

  // /ActualText replaces everything drawn inside its marked-content span. The
  // span is emitted at the position of the first glyph *inside* it, not at the
  // BDC, which is typically still at the origin.
  final actualTextStack = <String?>[];
  var suppressDepth = 0;
  String? pendingActualText;

  double num(PdfObj o) => o is PdfNumObj ? o.value : 0;

  /// Device-space position of the current text origin.
  (double, double) devicePosition() => (
        ctm[0] * tx + ctm[2] * ty + ctm[4],
        ctm[1] * tx + ctm[3] * ty + ctm[5],
      );

  void emit(String text, {FontInfo? font}) {
    // An empty show is how a producer reopens a text object after a marked
    // content operator; it must not decide where the span sits.
    if (text.isEmpty) return;
    final pending = pendingActualText;
    if (pending != null) {
      pendingActualText = null;
      final (px, py) = devicePosition();
      runs.add(TextRun(
        text: pending,
        font: currentFont,
        x: px,
        y: py,
        fontSize: fontSize,
      )..objectIndex = objectIndex);
    }
    if (suppressDepth > 0) return; // inside an /ActualText span
    final (px, py) = devicePosition();
    runs.add(TextRun(
      text: text,
      font: font ?? currentFont,
      x: px,
      y: py,
      fontSize: fontSize,
    )..objectIndex = objectIndex);
  }

  // Glyphs from a font whose mapping cannot be trusted, collected until the run
  // they belong to ends. They are read back through the font as a whole,
  // because Bengali is drawn out of typing order and a producer is free to
  // split a cluster across operators: Word shows one glyph per `Tj`, so no
  // single operator ever holds a vowel sign together with the consonant it
  // precedes.
  var glyphRun = <int>[];
  FontInfo? glyphRunFont;
  // Where the run started. Positioning inside it moves the pen, so the run is
  // placed where its first glyph was drawn, not where the pen ends up.
  TextRun? glyphRunAt;
  // Device x where the run's next glyph would start if nothing moved the pen,
  // and the pen position the last show began from. This walker does not
  // advance the pen on a show, so an unchanged position means "continue".
  var glyphRunPenX = 0.0;
  (double, double)? lastShowAt;

  void flushGlyphRun() {
    final font = glyphRunFont;
    final codes = glyphRun;
    final at = glyphRunAt;
    glyphRun = <int>[];
    glyphRunFont = null;
    glyphRunAt = null;
    lastShowAt = null;
    if (font == null || at == null || codes.isEmpty) return;
    final text = font.unshapeRun(codes);
    if (text.isEmpty) return;
    runs.add(TextRun(
      text: text,
      font: font,
      x: at.x,
      y: at.y,
      fontSize: at.fontSize,
    )..objectIndex = at.objectIndex);
  }

  /// Adds the glyphs of one show to the pending run.
  ///
  /// [width] is how far the show moves the pen, in units of the font size, as
  /// drawn — glyph advances less any `TJ` adjustments.
  void collect(FontInfo font, List<int> codes, double width) {
    if (!codes.any((code) => code >= 0)) {
      // Nothing drawn, but perhaps a space meant: see [shownCodes].
      if (codes.contains(kWordGap) &&
          glyphRunAt != null &&
          (glyphRun.isEmpty || glyphRun.last != kWordGap)) {
        glyphRun.add(kWordGap);
      }
      return;
    }
    final (x, y) = devicePosition();
    final scale = ctm[0].abs() == 0 ? 1.0 : ctm[0].abs();
    final em = fontSize * scale;

    final at = glyphRunAt;
    if (at != null) {
      final limit = (at.fontSize > fontSize ? at.fontSize : fontSize) * 0.4;
      if (!identical(glyphRunFont, font) || (y - at.y).abs() > limit) {
        flushGlyphRun();
      }
    }

    final last = lastShowAt;
    final moved = last == null || last.$1 != x || last.$2 != y;
    final start = glyphRunAt == null || moved ? x : glyphRunPenX;
    if (glyphRunAt == null) {
      glyphRunAt = TextRun(text: '', font: font, x: x, y: y, fontSize: fontSize)
        ..objectIndex = objectIndex;
    } else if (start - glyphRunPenX > em * 0.25 &&
        (glyphRun.isEmpty || glyphRun.last != kWordGap)) {
      // Empty space between the last glyph and this one, with nothing drawn
      // in it: a word gap written by moving the pen rather than with a space.
      glyphRun.add(kWordGap);
    }

    glyphRunFont = font;
    glyphRun.addAll(codes);
    glyphRunPenX = start + width * em;
    lastShowAt = (x, y);
  }

  /// The glyph codes one string shows, for reading glyphs back.
  ///
  /// Word writes the spaces of Bangla text as `( ) TJ` — a single space byte
  /// with the two-byte font still selected. That byte names no glyph and moves
  /// no pen in [FontInfo.glyphCodes], but it is where the author typed a space,
  /// and the next word is often placed less than a quarter em further on.
  List<int> shownCodes(FontInfo font, Uint8List bytes) {
    final codes = font.glyphCodes(bytes);
    if (font.twoByte && bytes.length.isOdd && bytes.last == 0x20) {
      codes.add(kWordGap);
    }
    return codes;
  }

  /// How far [codes] move the pen, in units of the font size.
  double widthOf(FontInfo font, List<int> codes) {
    final face = font.embedded;
    if (face == null || face.unitsPerEm == 0) return 0;
    var units = 0;
    for (final code in codes) {
      if (code >= 0) units += face.advance(font.glyphFor(code));
    }
    return units / face.unitsPerEm;
  }

  /// Whether glyphs shown with [font] are collected and read back as a run.
  bool readsGlyphsBack(FontInfo font) =>
      font.textMappingUntrusted &&
      suppressDepth == 0 &&
      pendingActualText == null;

  String decode(PdfStringObj s) {
    final font = currentFont;
    if (font == null) return s.asLatin1;

    // Nothing trustworthy says what these codes mean — no mapping at all, or a
    // /ToUnicode that contradicts the font it describes — so read the glyphs
    // back through the embedded font instead. Never for a font whose mapping
    // agrees with it: that is authoritative, and this is inference.
    if (font.textMappingUntrusted) {
      final unshaped = font.unshape(font.codes(s.bytes));
      if (unshaped != null) return unshaped;
    }

    final buffer = StringBuffer();
    for (final code in font.codes(s.bytes)) {
      final mapped = font.unicodeFor(code);
      if (mapped != null) {
        buffer.write(mapped);
      } else if (!font.twoByte && code >= 0x20 && code < 0x100) {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  while (true) {
    final token = lexer.next();
    if (token == null) break;
    if (token is! PdfOperatorObj) {
      operands.add(token);
      if (operands.length > 64) operands.removeAt(0);
      continue;
    }

    // A run ends at anything that moves the pen somewhere unrelated or changes
    // what the glyphs mean. A font change is caught when the next glyph
    // arrives, and a change of line by [collect].
    if (_runBreakingOperators.contains(token.name)) flushGlyphRun();

    switch (token.name) {
      case 'q':
        ctmStack.add(List<double>.of(ctm));
      case 'Q':
        if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
      case 'cm':
        if (operands.length >= 6) {
          final m = <double>[
            for (var i = 6; i >= 1; i--) num(operands[operands.length - i]),
          ];
          // CTM' = m x CTM
          ctm = <double>[
            m[0] * ctm[0] + m[1] * ctm[2],
            m[0] * ctm[1] + m[1] * ctm[3],
            m[2] * ctm[0] + m[3] * ctm[2],
            m[2] * ctm[1] + m[3] * ctm[3],
            m[4] * ctm[0] + m[5] * ctm[2] + ctm[4],
            m[4] * ctm[1] + m[5] * ctm[3] + ctm[5],
          ];
        }
      case 'BT':
        objectIndex++;
        tx = ty = lineX = lineY = 0;
      case 'ET':
        break;
      case 'Tf':
        if (operands.length >= 2) {
          final name = operands[operands.length - 2];
          if (name is PdfNameObj) currentFont = fonts[name.value];
          fontSize = num(operands.last);
        }
      case 'TL':
        if (operands.isNotEmpty) leading = num(operands.last);
      case 'Td':
        if (operands.length >= 2) {
          lineX += num(operands[operands.length - 2]);
          lineY += num(operands.last);
          tx = lineX;
          ty = lineY;
        }
      case 'TD':
        if (operands.length >= 2) {
          leading = -num(operands.last);
          lineX += num(operands[operands.length - 2]);
          lineY += num(operands.last);
          tx = lineX;
          ty = lineY;
        }
      case 'Tm':
        if (operands.length >= 6) {
          lineX = num(operands[operands.length - 2]);
          lineY = num(operands.last);
          tx = lineX;
          ty = lineY;
        }
      case 'T*':
        lineY -= leading;
        tx = lineX;
        ty = lineY;
      case 'Tj':
      case "'":
      case '"':
        if (token.name != 'Tj') {
          lineY -= leading;
          tx = lineX;
          ty = lineY;
        }
        final s = operands.isEmpty ? null : operands.last;
        final font = currentFont;
        if (s is PdfStringObj) {
          if (font != null && readsGlyphsBack(font)) {
            final codes = shownCodes(font, s.bytes);
            collect(font, codes, widthOf(font, codes));
          } else {
            flushGlyphRun();
            emit(decode(s));
          }
        }
      case 'TJ':
        final array = operands.isEmpty ? null : operands.last;
        final font = currentFont;
        if (array is PdfArrayObj && font != null && readsGlyphsBack(font)) {
          final codes = <int>[];
          var width = 0.0;
          for (final item in array.values) {
            if (item is PdfStringObj) {
              final shown = shownCodes(font, item.bytes);
              codes.addAll(shown);
              width += widthOf(font, shown);
            } else if (item is PdfNumObj) {
              // Adjustments are in thousandths of the font size, subtracted.
              width -= item.value / 1000;
              if (item.value <= -120) codes.add(kWordGap);
            }
          }
          collect(font, codes, width);
        } else if (array is PdfArrayObj) {
          flushGlyphRun();
          final buffer = StringBuffer();
          for (final item in array.values) {
            if (item is PdfStringObj) {
              buffer.write(decode(item));
            } else if (item is PdfNumObj && item.value <= -120) {
              // A large negative kern is how most producers write a space.
              buffer.write(' ');
            }
          }
          emit(buffer.toString());
        }
      case 'BDC':
        String? actual;
        if (operands.length >= 2) {
          final props = operands.last;
          if (props is PdfDictObj) {
            final at = props['ActualText'];
            if (at is PdfStringObj) actual = _utf16(at.bytes);
          }
        }
        actualTextStack.add(actual);
        if (actual != null) {
          flushGlyphRun();
          // The span's own text is authoritative; the glyphs inside it are
          // ignored, and it is positioned by the first of them.
          pendingActualText = actual;
          actualTextUsed = true;
          suppressDepth++;
        }
      case 'BMC':
        actualTextStack.add(null);
      case 'EMC':
        if (actualTextStack.isNotEmpty) {
          final popped = actualTextStack.removeLast();
          if (popped != null) {
            flushGlyphRun();
            if (suppressDepth > 0) suppressDepth--;
            // A span that drew nothing still carries its text.
            final pending = pendingActualText;
            if (pending != null) {
              pendingActualText = null;
              final (px, py) = devicePosition();
              runs.add(TextRun(
                text: pending,
                font: currentFont,
                x: px,
                y: py,
                fontSize: fontSize,
              )..objectIndex = objectIndex);
            }
          }
        }
      case 'Do':
        // An XObject: could be an image or a nested form. Counting it is
        // enough to recognise a scanned page.
        imageCount++;
      case 'BI':
        imageCount++;
      default:
        break;
    }
    operands.clear();
  }
  flushGlyphRun();

  return PageContent(
    runs: runs,
    imageCount: imageCount,
    actualTextUsed: actualTextUsed,
  );
}

String _utf16(Uint8List bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  if (units.isNotEmpty && units.first == 0xFEFF) units.removeAt(0);
  if (units.isEmpty) return String.fromCharCodes(bytes);
  return String.fromCharCodes(units);
}
