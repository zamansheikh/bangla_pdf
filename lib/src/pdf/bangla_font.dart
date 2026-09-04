/// The widget-level font handle for the Unicode shaping pipeline.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/pdf/shaped_pdf_font.dart';
import 'package:bangla_pdf/src/shaping/bengali_shaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A Unicode Bangla font: parses the TTF once, shapes with the font's own
/// GSUB/GPOS, and registers a glyph-addressed CID font in the document.
///
/// Contrast with `pw.Font.ttf`, which can only draw glyphs reachable from a
/// `cmap` entry and writes a one-rune-per-CID `/ToUnicode`.
class BanglaUnicodeFont extends pw.Font {
  BanglaUnicodeFont._(this.otf, this.shaper);

  /// Parses [data]. Returns `null` when the bytes are not a usable font.
  static BanglaUnicodeFont? tryParse(ByteData data) {
    final otf = OtFont.parse(data);
    if (otf == null) return null;
    return BanglaUnicodeFont._(otf, BengaliShaper(otf));
  }

  /// The parsed font tables.
  final OtFont otf;

  /// The shaper bound to [otf].
  final BengaliShaper shaper;

  /// Whether this font can actually shape Bangla, as opposed to being a Latin
  /// or legacy 8-bit font that merely happens to have been supplied.
  bool get canShapeBangla => shaper.canShape;

  @override
  String get fontName => otf.postScriptName;

  final Map<PdfDocument, ShapedPdfFont> _built = <PdfDocument, ShapedPdfFont>{};

  /// The document-level CID font, created on first use per document.
  ShapedPdfFont pdfFontFor(PdfDocument document) =>
      _built.putIfAbsent(document, () => ShapedPdfFont.create(document, otf));

  @override
  PdfFont buildFont(PdfDocument document) => pdfFontFor(document);

  /// Shapes [text] with this font.
  ShapedRun shape(String text) => shaper.shape(text);

  /// Ascent above the baseline, as a fraction of the em.
  double get ascent => otf.ascender / otf.unitsPerEm;

  /// Descent below the baseline (negative), as a fraction of the em.
  double get descent => otf.descender / otf.unitsPerEm;

  @override
  String toString() => '<BanglaUnicodeFont "$fontName">';
}
